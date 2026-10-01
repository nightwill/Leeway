import Foundation

/// The effort Claude Code starts new sessions on a model at: the
/// `modelSettings.<model>.effortLevel` key of its settings file, which is where
/// `/effort` leaves the choice too.
///
/// A level may be filed under an alias as well as under a model's id, and the
/// CLI resolves both to the model a session runs. The id wins where both are
/// set, and `/effort` files under the id, so a level it saved outranks one
/// filed here under the alias.
enum ClaudeEffortSetting {

    /// What the settings file accepts. Max lasts one session and is never
    /// written, and a model without the higher levels is held to its own cap
    /// by the CLI, which alone knows where that cap is.
    static let levels = ["low", "medium", "high", "xhigh"]

    /// The level filed under each key.
    static func levels(in settings: [String: Any]) -> [String: String] {
        let entries = settings[Key.modelSettings] as? [String: [String: Any]] ?? [:]
        return entries.compactMapValues { $0[Key.effortLevel] as? String }
    }

    /// `nil` takes the level out, which leaves the model its own default. An
    /// entry left with nothing else in it goes too, and so does an empty
    /// `modelSettings`, so the file ends as it would have without the app.
    static func set(_ level: String?, under key: String, in settings: inout [String: Any]) {
        var entries = settings[Key.modelSettings] as? [String: Any] ?? [:]
        var entry = entries[key] as? [String: Any] ?? [:]
        entry[Key.effortLevel] = level
        entries[key] = entry.isEmpty ? nil : entry
        settings[Key.modelSettings] = entries.isEmpty ? nil : entries
    }

    /// The status line reports a model with its context window appended, as in
    /// `claude-fable-5-1[1m]`, and the setting is filed without it.
    static func key(for model: String) -> String {
        guard let bracket = model.firstIndex(of: "[") else { return model }
        return String(model[..<bracket])
    }

    /// Asks the login shell whether the environment names a level of its own
    /// and keeps the answer, which is slow enough to belong off the main thread.
    static func refreshEnvironmentLevel() { environment.refresh() }

    /// The environment beats every setting, `/effort` included. `unset` and
    /// `auto` are the variable standing aside rather than naming a level.
    static var caveat: String? {
        guard let imposed = environment.value?.lowercased(), !["unset", "auto"].contains(imposed) else { return nil }
        return String(localized: "CLAUDE_CODE_EFFORT_LEVEL is set to \(imposed) — new sessions use that while it is set.")
    }

    private static let environment = LoginVariable(name: "CLAUDE_CODE_EFFORT_LEVEL", defaultsKey: "claude.environmentEffort")

    private enum Key {
        static let modelSettings = "modelSettings"
        static let effortLevel = "effortLevel"
    }
}
