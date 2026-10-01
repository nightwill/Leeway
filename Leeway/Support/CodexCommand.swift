import Foundation

/// What every call into the Codex CLI needs before it can run: where the CLI is
/// and the environment it has to be run under.
///
/// Finder hands the app launchd's environment, which has read no profile, so
/// neither the CLI's place on `PATH` nor a custom `CODEX_HOME` is in it — and
/// Codex looks its credentials up under the home it is given, so a run that
/// names the wrong one is a run that is not signed in.
enum CodexCommand {

    enum Failure: LocalizedError {
        case executableNotFound
        case signInRequired
        case subscriptionRequired
        case unreadable
        case unsupportedWindows
        case timedOut
        case reported(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                String(localized: "Codex was not found. Install the Codex CLI or add codex to PATH.")
            case .signInRequired:
                String(localized: "Sign in to Codex with your ChatGPT account by running codex login.")
            case .subscriptionRequired:
                String(localized: "Codex subscription limits require a ChatGPT account. API-key usage is not supported.")
            case .unreadable:
                String(localized: "Codex returned an unreadable response. Check that your Codex CLI is up to date.")
            case .unsupportedWindows:
                String(localized: "Codex returned quota windows other than 5 hours or 7 days.")
            case .timedOut:
                String(localized: "Codex did not answer in time.")
            case .reported(let message):
                String(localized: "Codex reported: \(message)")
            }
        }
    }

    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Finder does not inherit the shell's PATH or custom Codex home.
        // Resolve both off the main thread, without inspecting auth files.
        for name in ["PATH", "CODEX_HOME"] {
            if name == "PATH" || environment[name] == nil,
               case .exported(let value) = LoginShell.reading(of: name) {
                environment[name] = value
            }
        }
        return environment
    }

    static func executable(in environment: [String: String]) -> URL? {
        let manager = FileManager.default
        let candidates = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [
            manager.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin",
            "/Applications/Codex.app/Contents/Resources",
        ]
        return candidates.map { URL(filePath: $0).appending(path: "codex") }
            .first { manager.isExecutableFile(atPath: $0.path) }
    }
}
