import Foundation

/// The model Claude Code starts new sessions on: the `model` key of its
/// settings file, which is where `/model` leaves the choice too.
///
/// Every entry carries the effort that model starts at, kept per model the way
/// `/effort` keeps it (see `ClaudeEffortSetting`).
///
/// A session already running is not addressed by any of this. It holds the
/// model it was started with until it ends.
enum ClaudeModelSetting {

    /// `lastModel` is the id the status line last reported. The provider's own
    /// choice has no key of its own to file a level under, and the model it
    /// resolved to last time is the closest thing on disk to one; without it
    /// that entry offers no levels.
    static func menu(lastModel: String?) throws -> ModelMenu {
        let settings = try ClaudeSettings.load()
        let current = settings[Key.model] as? String
        var options = families + additional()
        if let current, !options.contains(where: { $0.id == current }) {
            options.append(.init(id: current, title: current))
        }
        let filed = ClaudeEffortSetting.levels(in: settings)
        options = options.map { option in
            var option = option
            guard let key = option.id ?? lastModel.map(ClaudeEffortSetting.key(for:)) else { return option }
            option.levels = ClaudeEffortSetting.levels
            option.effortKey = key
            option.effort = filed[key]
            return option
        }
        let caveats = [caveat(against: current), ClaudeEffortSetting.caveat].compactMap { $0 }
        return ModelMenu(options: options, current: current, caveats: caveats)
    }

    /// Writes the model and, for an entry that has levels, the level it
    /// starts at, in one go. A `nil` model takes the key out, which is what
    /// leaves Claude Code its own choice; a `nil` level does the same for the
    /// level.
    static func set(_ option: ModelMenu.Option, effort: String?) throws {
        var settings = try ClaudeSettings.load()
        settings[Key.model] = option.id
        if let key = option.effortKey {
            ClaudeEffortSetting.set(effort, under: key, in: &settings)
        }
        try ClaudeSettings.save(settings)
    }

    /// Asks the login shell whether the environment names a model of its own
    /// and keeps the answer, which is slow enough to belong off the main thread.
    static func refreshEnvironmentModel() { environment.refresh() }

    /// The environment has the last word, and a menu that let the file answer
    /// for it would be naming a model no new session is going to run.
    ///
    /// The same value on both sides is nothing to say: the setting stands, and
    /// the panel would only be reporting that it was agreed with.
    private static func caveat(against current: String?) -> String? {
        guard let imposed = environment.value, imposed != current else { return nil }
        return String(localized: "ANTHROPIC_MODEL is set to \(imposed) — new sessions use that while it is set.")
    }

    /// A variable the CLI reads before it reads anything of its own.
    private static let environment = LoginVariable(name: "ANTHROPIC_MODEL", defaultsKey: "claude.environmentModel")

    /// The standing families, by alias rather than by version on purpose: an
    /// alias is a standing order for the newest model of its family, so a
    /// choice made here still means what it meant after the next release, where
    /// a pinned version quietly turns into last year's model.
    private static let families: [ModelMenu.Option] = [
        .init(id: nil, title: String(localized: "Default")),
        .init(id: "opus", title: "Opus"),
        .init(id: "sonnet", title: "Sonnet"),
        .init(id: "haiku", title: "Haiku"),
        .init(id: "opusplan", title: "Opus Plan"),
    ]

    /// Models outside the standing families that this account has been offered.
    ///
    /// Which ones those are is decided per account and served to the CLI, so
    /// the app has no list of its own to consult and no business guessing: the
    /// menu Claude Code caches for itself is the one place on disk that knows,
    /// and a model missing from it is a model the account cannot run anyway.
    private static func additional() -> [ModelMenu.Option] {
        guard let data = try? Data(contentsOf: ClaudeDirectory.globalConfigURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cached = config[Key.additionalModels] as? [[String: Any]] else { return [] }
        return cached.compactMap { entry in
            guard let id = entry[Key.value] as? String else { return nil }
            return ModelMenu.Option(id: id, title: entry[Key.label] as? String ?? id)
        }
    }

    private enum Key {
        static let model = "model"
        static let additionalModels = "additionalModelOptionsCache"
        static let value = "value"
        static let label = "label"
    }
}
