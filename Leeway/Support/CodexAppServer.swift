import Foundation

/// A session on the Codex CLI's own local app-server: the process, the
/// handshake it opens with, and the line-framed requests that follow.
///
/// Everything the app asks of Codex goes through one of these, because the CLI
/// is the only thing that may touch the account: it owns authentication, token
/// refresh and the formatting of a configuration file the user writes by hand.
/// A second reader of any of the three would be a second thing to keep right.
enum CodexAppServer {

    typealias Failure = CodexCommand.Failure

    /// Runs an exchange against a server of its own, off the main thread —
    /// every step of it blocks, from starting the process to waiting on a reply.
    static func session<T>(timeout: TimeInterval = defaultTimeout, _ exchange: @escaping (inout Connection) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try run(timeout: timeout, exchange) })
            }
        }
    }

    static func run<T>(timeout: TimeInterval = defaultTimeout, _ exchange: (inout Connection) throws -> T) throws -> T {
        let environment = CodexCommand.environment()
        guard let executable = CodexCommand.executable(in: environment) else { throw Failure.executableNotFound }
        return try run(executable: executable, environment: environment, timeout: timeout, exchange)
    }

    /// The explicit executable also lets the protocol be checked against a
    /// fixture server.
    static func run<T>(
        executable: URL,
        environment: [String: String],
        timeout: TimeInterval = defaultTimeout,
        _ exchange: (inout Connection) throws -> T
    ) throws -> T {
        var answer: T?
        // `ChildProcess` takes its exchange as an optional, which makes it
        // escaping as far as the compiler is concerned. It outlives nothing:
        // the run is over before this call returns.
        let report = try withoutActuallyEscaping(exchange) { exchange in
            try ChildProcess.run(
                executable,
                arguments: ["app-server"],
                environment: environment,
                keepingStandardError: false,
                timeout: timeout
            ) { input, output in
                var connection = Connection(input: input, output: output)
                try connection.handshake()
                answer = try exchange(&connection)
                // What the exchange made of the conversation is already in
                // hand. The transport deliberately stops the server after the
                // last reply, so neither its output nor its exit status
                // describes the request.
                return ""
            }
        }
        guard !report.timedOut else { throw Failure.timedOut }
        guard let answer else { throw Failure.unreadable }
        return answer
    }

    /// Long enough for a CLI that may have to start and refresh a token first.
    static let defaultTimeout: TimeInterval = 30

    struct Connection {
        let input: FileHandle
        let output: FileHandle
        private var buffer = Data()
        private var nextID = 0

        init(input: FileHandle, output: FileHandle) {
            self.input = input
            self.output = output
        }

        /// Opens the session. The server answers nothing until it has been told
        /// who is asking.
        mutating func handshake() throws {
            _ = try request("initialize", params: ["clientInfo": ["name": "leeway", "version": "1.0"]])
            try send(["method": "initialized"])
        }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            do {
                try input.write(contentsOf: data)
            } catch {
                throw Failure.unreadable
            }
        }

        @discardableResult
        mutating func request(_ method: String, params: [String: Any] = [:]) throws -> [String: Any] {
            let id = nextID
            nextID += 1
            try send(["method": method, "id": id, "params": params])
            while true {
                let line = try nextLine()
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw Failure.unreadable
                }
                guard message["id"] as? Int == id else { continue }
                if let error = message["error"] as? [String: Any], let detail = error["message"] as? String {
                    throw Failure.reported(detail)
                }
                guard let result = message["result"] as? [String: Any] else { throw Failure.unreadable }
                return result
            }
        }

        private mutating func nextLine() throws -> Data {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    if !line.isEmpty { return line }
                } else {
                    guard buffer.count < 1_048_576 else { throw Failure.unreadable }
                    // A request/response pipe cannot wait to fill a requested
                    // byte count: the server is waiting for our next message.
                    let chunk = output.availableData
                    guard !chunk.isEmpty else { throw Failure.unreadable }
                    buffer.append(chunk)
                }
            }
        }
    }
}
