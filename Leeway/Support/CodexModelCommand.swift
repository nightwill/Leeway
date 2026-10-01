import Foundation

/// Reads and sets the model Codex starts new sessions on, and the reasoning
/// effort it starts them at.
///
/// Codex keeps one level for whatever model is chosen, but each model lists the
/// levels it takes, so every entry offers its own model's levels and all of
/// them show the one level that is set.
///
/// Both go through the CLI rather than through `config.toml`: it is the only
/// thing that knows which models the account may run, and the file is the
/// user's own — hand-written, commented, full of sections this app has no
/// business rewriting to change one line in it.
enum CodexModelCommand {

    typealias Failure = CodexCommand.Failure

    static func menu() async throws -> ModelMenu {
        try await CodexAppServer.session { try menu(over: &$0) }
    }

    /// Asks an open server which models the account may run and which of them
    /// the configuration names.
    static func menu(over connection: inout CodexAppServer.Connection) throws -> ModelMenu {
        let listed = try connection.request("model/list")
        let configuration = try connection.request("config/read")[Key.config] as? [String: Any]
        let effort = configuration?[Key.effort] as? String
        return ModelMenu(options: try options(from: listed, effort: effort), current: configuration?[Key.model] as? String)
    }

    /// `nil` takes a key out of the file, which is what leaves Codex its own
    /// choice of model, or each model its own default level. Without `effort`
    /// the level stays as it is, which is what an entry without levels asks.
    static func set(_ model: String?, effort: String?? = .none) async throws {
        _ = try await CodexAppServer.session { try set(model, effort: effort, over: &$0) }
    }

    static func set(_ model: String?, effort: String?? = .none, over connection: inout CodexAppServer.Connection) throws {
        try write(model, to: Key.model, over: &connection)
        if case .some(let effort) = effort {
            try write(effort, to: Key.effort, over: &connection)
        }
    }

    private static func write(_ value: String?, to keyPath: String, over connection: inout CodexAppServer.Connection) throws {
        try connection.request("config/value/write", params: [
            "keyPath": keyPath,
            // A name with nothing to name is the key going away, and JSON has
            // to be handed the null itself to say so.
            "value": value ?? NSNull(),
            // One key holds one value, so a write replaces what is there
            // rather than merging anything into it.
            "mergeStrategy": "replace",
        ])
    }

    /// The provider's own choice takes the levels of the model Codex marks as
    /// its default, which is the one it resolves to.
    private static func options(from listed: [String: Any], effort: String?) throws -> [ModelMenu.Option] {
        guard let models = listed[Key.data] as? [[String: Any]] else { throw Failure.unreadable }
        let fallback = models.first { $0[Key.isDefault] as? Bool == true }
        let automatic = ModelMenu.Option(id: nil, title: String(localized: "Default"), levels: fallback.flatMap(levels(of:)), effort: effort)
        return [automatic] + models.compactMap { model in
            // Hidden is Codex saying the model is not for choosing from a menu.
            guard model[Key.hidden] as? Bool != true, let id = model[Key.id] as? String else { return nil }
            return ModelMenu.Option(id: id, title: model[Key.displayName] as? String ?? id, levels: levels(of: model), effort: effort)
        }
    }

    /// `nil` when the listing says nothing about levels for the model, so the
    /// entry does not offer an empty choice.
    private static func levels(of model: [String: Any]) -> [String]? {
        let levels = (model[Key.supportedEfforts] as? [[String: Any]] ?? []).compactMap { $0[Key.supportedEffort] as? String }
        return levels.isEmpty ? nil : levels
    }

    private enum Key {
        static let model = "model"
        static let config = "config"
        static let data = "data"
        static let id = "id"
        static let displayName = "displayName"
        static let hidden = "hidden"
        static let isDefault = "isDefault"
        static let effort = "model_reasoning_effort"
        static let supportedEfforts = "supportedReasoningEfforts"
        static let supportedEffort = "reasoningEffort"
    }
}
