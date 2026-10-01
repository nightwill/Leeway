import Foundation

/// Installs and removes the `statusLine` hook that feeds Leeway.
///
/// Claude Code passes its status JSON — limits included — to whatever command is
/// configured as `statusLine`. The bridge stores that JSON for the app and then
/// hands stdin to the command that was configured before, if there was one.
enum StatusLineBridge {

    enum Status: Equatable {
        case installed
        case missing
        case foreign(command: String)
    }

    enum Failure: LocalizedError {
        case bundleScriptMissing

        var errorDescription: String? {
            switch self {
            case .bundleScriptMissing: String(localized: "The bridge script is missing from the app bundle.")
            }
        }
    }

    static func status() -> Status {
        guard let statusLine = (try? ClaudeSettings.load())?[Key.statusLine] as? [String: Any],
              let command = statusLine[Key.command] as? String else {
            return .missing
        }
        return command == ClaudeDirectory.bridgeURL.path ? .installed : .foreign(command: command)
    }

    static func install() throws {
        try installScript()

        if case .foreign(let command) = status() {
            try inherit(command: command)
        }
        try ClaudeSettings.set(Key.statusLine, to: [Key.type: "command", Key.command: ClaudeDirectory.bridgeURL.path])
    }

    static func uninstall() throws {
        if case .installed = status() {
            if let inherited = inheritedCommand() {
                try ClaudeSettings.set(Key.statusLine, to: [Key.type: "command", Key.command: inherited])
            } else {
                try ClaudeSettings.remove(Key.statusLine)
            }
        }
        try? FileManager.default.removeItem(at: ClaudeDirectory.bridgeURL)
        try? FileManager.default.removeItem(at: ClaudeDirectory.inheritedBridgeURL)
    }

    private enum Key {
        static let statusLine = "statusLine"
        static let command = "command"
        static let type = "type"
    }

    private static func installScript() throws {
        guard let source = Bundle.main.url(forResource: "leeway-statusline", withExtension: "sh") else {
            throw Failure.bundleScriptMissing
        }
        try FileManager.default.createDirectory(at: ClaudeDirectory.url, withIntermediateDirectories: true)
        let script = try Data(contentsOf: source)
        try script.write(to: ClaudeDirectory.bridgeURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ClaudeDirectory.bridgeURL.path)
    }

    /// Keeps a previously configured status line alive behind the bridge.
    private static func inherit(command: String) throws {
        let script = "#!/bin/sh\n\(command)\n"
        try Data(script.utf8).write(to: ClaudeDirectory.inheritedBridgeURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ClaudeDirectory.inheritedBridgeURL.path
        )
    }

    private static func inheritedCommand() -> String? {
        guard let text = try? String(contentsOf: ClaudeDirectory.inheritedBridgeURL, encoding: .utf8) else { return nil }
        let body = text.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}
