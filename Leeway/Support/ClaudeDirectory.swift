import Foundation

/// Location of the Claude Code configuration directory and the files Leeway
/// exchanges with it. Everything else derives its paths from here.
enum ClaudeDirectory {

    /// The variable the CLI reads its configuration directory from. What it
    /// holds decides more than a path: the CLI derives the name it looks its
    /// credentials up by from it too, so a run has to see it exactly as the
    /// terminal the user logged in from saw it. See `ClaudeCommand`.
    static let configDirectoryKey = "CLAUDE_CONFIG_DIR"

    /// The directory the CLI would resolve: the variable where there is one,
    /// `~/.claude` where there is not.
    ///
    /// The value is taken as literally as the CLI takes it — no tilde expansion.
    /// A shell expands `~` before the variable is ever set, so a tilde that
    /// survives into the environment was quoted on purpose, and expanding it
    /// here would point the app at a directory the CLI never looks in.
    static var url: URL {
        if let configuredPath { return URL(filePath: configuredPath) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    /// What the variable holds for the CLI, `nil` when it holds nothing.
    static var configuredPath: String? { directory.value }

    /// Asks the login shell where the directory is and keeps the answer. The
    /// asking is slow enough to belong off the main thread, and the paths are
    /// wanted from the app's first frame, so only the very first launch has to
    /// open on a guess.
    static func refreshConfiguredPath() { directory.refresh() }

    /// Where the bridge script parks the latest `statusLine` JSON.
    static var stateURL: URL { url.appending(path: "leeway.json") }

    /// The bridge script itself, installed from the app bundle.
    static var bridgeURL: URL { url.appending(path: "leeway-statusline.sh") }

    /// A `statusLine` command that was configured before Leeway took over.
    static var inheritedBridgeURL: URL { url.appending(path: "leeway-inner.sh") }

    static var settingsURL: URL { url.appending(path: "settings.json") }

    /// The CLI's own configuration file, which is where it caches the models
    /// this account may use. It is the one thing Claude Code does not keep in
    /// the configuration directory: named home, it sits beside it.
    static var globalConfigURL: URL {
        let home = configuredPath.map { URL(filePath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude.json")
    }

    private static let directory = LoginVariable(name: configDirectoryKey, defaultsKey: "claude.configDirectory")
}
