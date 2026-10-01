import Foundation

/// Reads a variable out of the user's login shell.
///
/// An app opened from Finder is handed launchd's environment, which has never
/// seen a shell profile: everything exported there — the Claude Code
/// configuration directory among it — is simply not in what we inherit, and the
/// terminal the user works in and the app looking over their shoulder disagree
/// about where Claude Code keeps its things. The only way to the value is to
/// start the shell the way a terminal starts it and ask.
enum LoginShell {

    /// What the login shell had to say about `name`.
    enum Reading: Equatable {
        case exported(String)
        case unset

        /// The shell could not be run, or did not answer in time. Nothing was
        /// learned, which is not the same as learning there is nothing.
        case unanswered
    }

    /// Asks the login shell what it exports under `name`.
    ///
    /// Costs a shell start-up, profile and all, so it belongs off the main
    /// thread and nowhere near a path lookup.
    static func reading(of name: String) -> Reading {
        guard let shellURL else { return .unanswered }

        // A profile prints things — a greeting, a version notice, a whole prompt
        // framework clearing its throat — so the value comes back fenced between
        // two control characters that nothing else has occasion to print, and is
        // cut out of the noise. `-i` on top of `-l` because zsh reads `.zshrc`
        // for interactive shells only, and `.zshrc` is where an export lives.
        let report = try? ChildProcess.run(
            shellURL,
            arguments: ["-l", "-i", "-c", "printf '\\1%s\\2' \"${\(name)-}\""],
            keepingStandardError: false,
            timeout: timeout
        )
        guard let report, !report.timedOut, report.status == 0,
              let value = value(fencedIn: report.output) else { return .unanswered }
        return value.isEmpty ? .unset : .exported(value)
    }

    private static let timeout: TimeInterval = 5

    private static var shellURL: URL? {
        let path = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return FileManager.default.isExecutableFile(atPath: path) ? URL(filePath: path) : nil
    }

    /// The text between the two fence characters, or `nil` when the fence is not
    /// there — which means the shell never reached the `printf`, not that the
    /// variable is empty.
    private static func value(fencedIn output: String) -> String? {
        guard let opening = output.firstIndex(of: "\u{01}"),
              let closing = output[opening...].firstIndex(of: "\u{02}") else { return nil }
        return String(output[output.index(after: opening)..<closing])
    }
}
