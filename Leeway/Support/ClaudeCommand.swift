import Foundation

/// Runs the Claude Code CLI and hands back what it printed.
///
/// Every caller wants the same three things of it, and each one is a trap on its
/// own: the executable found wherever it happens to be installed, the output
/// drained while the process is still running, and a deadline on a command that
/// may never answer.
enum ClaudeCommand {

    enum Failure: LocalizedError {
        case executableNotFound
        case launchFailed(String)
        case failed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                String(localized: "Claude Code was not found. Install it or add the claude command to PATH.")
            case .launchFailed(let message):
                String(localized: "Claude Code could not be launched: \(message)")
            case .failed(let message):
                String(localized: "Claude Code reported: \(message)")
            case .timedOut:
                String(localized: "Claude Code did not answer in time.")
            }
        }
    }

    /// Runs the CLI and returns everything it printed.
    static func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        guard let executableURL else { throw Failure.executableNotFound }

        // Every step of the run blocks, so none of them may be on the main thread.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try run(executableURL, arguments, timeout) })
            }
        }
    }

    private static func run(_ executableURL: URL, _ arguments: [String], _ timeout: TimeInterval) throws -> String {
        let report: ChildProcess.Report
        do {
            report = try ChildProcess.run(
                executableURL,
                arguments: arguments,
                environment: environment,
                keepingStandardError: true,
                timeout: timeout
            )
        } catch {
            throw Failure.launchFailed(error.localizedDescription)
        }

        guard report.status == 0 else {
            // Past the deadline the process is one we killed, so its status says
            // nothing about what Claude Code made of the request.
            if report.timedOut { throw Failure.timedOut }
            throw Failure.failed(report.complaint ?? statusReport(report.status))
        }
        return report.output
    }

    /// The environment a run gets, which has to be the one the user logged in
    /// under. The CLI derives the name it looks its credentials up by from the
    /// configuration directory variable, so naming a directory the user did not
    /// name — even the very `~/.claude` the CLI would have used on its own —
    /// sends it looking where nothing was ever stored, and the run answers
    /// "Not logged in · Please run /login". Leaving the variable out when the
    /// user does name one lands in the same place from the other side.
    ///
    /// Ours passes across untouched, which is right whenever the app was opened
    /// from a terminal: the shell that set the variable for the app set it for
    /// the user's own sessions too. Opened from Finder we were handed launchd's
    /// environment, which has read no profile, and the one thing added here is
    /// the variable the login shell does export and we were never given.
    ///
    /// `nil` asks for ours, inherited whole.
    private static var environment: [String: String]? {
        let inherited = ProcessInfo.processInfo.environment
        guard inherited[ClaudeDirectory.configDirectoryKey] == nil,
              let path = ClaudeDirectory.configuredPath else { return nil }
        var environment = inherited
        environment[ClaudeDirectory.configDirectoryKey] = path
        return environment
    }

    private static func statusReport(_ status: Int32) -> String {
        String(localized: "the command exited with status \(status).")
    }

    private static var executableURL: URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "claude").path }

        return candidates
            .first(where: fileManager.isExecutableFile(atPath:))
            .map { URL(filePath: $0) }
    }
}
