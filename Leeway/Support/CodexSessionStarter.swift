import Foundation

/// Starts the smallest turn the Codex CLI will take, so an idle account receives
/// a fresh five-hour quota window at a moment of the user's choosing.
///
/// Unlike the Claude starter this one spends a little of the very window it
/// opens: Codex anchors the window to the first request after the last reset,
/// and reading the quotas is not a request against them, so nothing but real
/// usage can open one. A couple of thousand tokens is what it costs.
enum CodexSessionStarter {

    static func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try startSynchronously() })
            }
        }
    }

    private static func startSynchronously() throws {
        let environment = CodexCommand.environment()
        guard let executable = CodexCommand.executable(in: environment) else {
            throw CodexCommand.Failure.executableNotFound
        }

        let report = try ChildProcess.run(
            executable,
            arguments: arguments,
            environment: environment,
            keepingStandardError: true,
            timeout: timeout
        )
        guard !report.timedOut else { throw CodexCommand.Failure.timedOut }
        guard report.status == 0 else {
            throw CodexCommand.Failure.reported(report.complaint ?? statusReport(report.status))
        }
    }

    /// The user's own configuration is left out on purpose. It names the model
    /// and the reasoning effort their work wants, along with whatever MCP
    /// servers and hooks come with it — none of which belong in a turn whose
    /// whole point is to be the cheapest request the account can make. Sign-in
    /// is untouched by that: credentials are read from `CODEX_HOME`, which the
    /// environment carries and the configuration file does not hold.
    ///
    /// `--ephemeral` keeps the turn out of the user's own sessions, and the
    /// read-only sandbox is the answer to a model that decides to look around:
    /// it has nothing to look for, and it will not be writing either way.
    private static let arguments = [
        "exec",
        "--ignore-user-config",
        "--ephemeral",
        "--skip-git-repo-check",
        "--sandbox", "read-only",
        "--color", "never",
        "-c", "model_reasoning_effort=low",
        ".",
    ]

    /// A turn this small answers in a few seconds. The rest of the allowance is
    /// for a slow answer rather than a stalled one, which the deadline ends so
    /// the button is not left spinning for good.
    private static let timeout: TimeInterval = 60

    private static func statusReport(_ status: Int32) -> String {
        String(localized: "the command exited with status \(status).")
    }
}
