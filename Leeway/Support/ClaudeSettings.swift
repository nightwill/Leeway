import Foundation

/// The Claude Code settings file, as a thing to change rather than to own.
///
/// Two settings the app puts there — the status line hook and the model new
/// sessions start on — sit in a file the user writes by hand and the CLI writes
/// behind them, so every change loads what is there, moves one key, and puts
/// the rest back exactly as it was found.
enum ClaudeSettings {

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "~/.claude/settings.json is not a JSON object.")
            }
        }
    }

    /// The settings as they stand. No file at all is the state before the first
    /// setting was ever made, not a fault.
    static func load() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: ClaudeDirectory.settingsURL) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        return object
    }

    /// Puts `value` under `key`, leaving every other setting where it was.
    static func set(_ key: String, to value: Any) throws {
        var settings = try load()
        settings[key] = value
        try save(settings)
    }

    /// Takes `key` out, which is not the same as setting it to anything: an
    /// absent key is what leaves Claude Code free to decide for itself.
    static func remove(_ key: String) throws {
        var settings = try load()
        guard settings.removeValue(forKey: key) != nil else { return }
        try save(settings)
    }

    static func save(_ settings: [String: Any]) throws {
        let backup = ClaudeDirectory.settingsURL.appendingPathExtension("leeway-backup")
        if FileManager.default.fileExists(atPath: ClaudeDirectory.settingsURL.path),
           !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: ClaudeDirectory.settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: ClaudeDirectory.settingsURL, options: .atomic)
    }
}
