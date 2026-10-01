import Foundation
import Darwin

/// Runs a child process to completion under a deadline and hands back what it
/// printed.
///
/// Both halves of that are traps rather than preferences. The output has to be
/// drained while the process is still running, or the pipe fills up and stops it
/// before it ever reaches the exit being waited for; and the deadline has to be
/// called off once the process is back, or it fires at one that is long gone.
enum ChildProcess {

    struct Report {
        let output: String
        let status: Int32

        /// Set when the deadline is what ended the run, in which case `status`
        /// says nothing about what the command made of the request.
        let timedOut: Bool

        /// The last thing the command said before giving up, which is the part
        /// that says why. All of it is no use to a panel this narrow, and a
        /// stack of it even less.
        var complaint: String? {
            output
                .split(whereSeparator: \.isNewline)
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Throws only what launching throws. A command that started and then failed
    /// comes back as a report carrying its status.
    static func run(
        _ executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        keepingStandardError: Bool,
        timeout: TimeInterval,
        exchange: ((FileHandle, FileHandle) throws -> String)? = nil
    ) throws -> Report {
        let process = Process()
        // One pipe for both streams where the error output is wanted. Two would
        // have to be drained at the same time or whichever went unread would
        // fill up and stop the process; a terminal shows them interleaved
        // anyway, and a caller that reads the output by the line can pass over
        // what it did not ask for.
        let pipe = Pipe()
        let input = exchange.map { _ in Pipe() }
        if let input {
            // A server can exit between two writes. Report EPIPE to the caller
            // instead of letting SIGPIPE terminate the menu bar app.
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if let environment { process.environment = environment }
        // A child left holding our own standard input could sit waiting on input
        // that is never coming.
        process.standardInput = input.map { $0 as Any } ?? FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = keepingStandardError ? pipe : FileHandle.nullDevice

        try process.run()

        let deadline = Date.now + timeout
        let expiry = DispatchWorkItem { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: expiry)

        // Reading to the end waits for the exit and empties the pipe in the one
        // step. Waiting without reading is the deadlock it looks like the long
        // way round.
        let output = Result<String, Error> {
            if let exchange, let input {
                return try exchange(input.fileHandleForWriting, pipe.fileHandleForReading)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let input {
            try? input.fileHandleForWriting.close()
            // An RPC server has no natural exit after answering a request.
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        expiry.cancel()
        let timedOut = Date.now >= deadline

        return Report(
            output: timedOut ? "" : try output.get(),
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
