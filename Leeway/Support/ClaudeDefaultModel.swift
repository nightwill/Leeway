import Foundation

/// The model Claude Code chooses for itself when its settings name none.
///
/// No file says which one that is: it follows the account's plan and what
/// Anthropic serves the CLI, and it moves with releases. The model the last
/// session ran on is no answer either, since that session may have been told
/// to run on something else. The CLI answers for itself, though: started with
/// `--model default`, which sets aside whatever the settings name, it reports
/// the model in the first event of its stream, and `/model` gives it a turn
/// that is answered without a request going out.
///
/// A run takes a second or two, so the last answer is kept: the panel opens on
/// it and corrects itself once the CLI has spoken.
enum ClaudeDefaultModel {

    struct Model: Equatable {
        /// The id a session runs on, as the CLI reports it.
        let id: String

        /// What Claude Code calls it, the id where it gave no name.
        let name: String
    }

    /// The last answer, `nil` until the CLI has given one.
    static var remembered: Model? {
        guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String],
              let id = stored[Key.id] else { return nil }
        return Model(id: id, name: stored[Key.name] ?? id)
    }

    /// Asks the CLI and keeps the answer, returning whether it changed.
    ///
    /// A run that fails leaves the last answer standing: it is the better
    /// guess of the two, and the next run corrects it.
    @discardableResult
    static func refresh() async -> Bool {
        guard let output = try? await ClaudeCommand.run(arguments, timeout: timeout),
              let model = model(in: output),
              model != remembered else { return false }
        UserDefaults.standard.set([Key.id: model.id, Key.name: model.name], forKey: defaultsKey)
        return true
    }

    private static let arguments = [
        "--print",
        "--model", "default",
        "--no-session-persistence",
        // The model is only reported in the streamed form, which the CLI
        // refuses to print without the verbose flag.
        "--output-format", "stream-json",
        "--verbose",
        "/model",
    ]

    /// The id comes from the stream's opening event. The name is only in the
    /// text `/model` prints, as in "Current model: `Fable 5.1` (effort: high)",
    /// so it is taken from between the first pair of backticks there, and a
    /// reworded text costs the name, never the model.
    static func model(in output: String) -> Model? {
        var id: String?
        var name: String?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch (event[Key.type] as? String, event[Key.subtype] as? String) {
            case ("system", "init"):
                id = event[Key.model] as? String
            case ("result", _):
                let parts = (event[Key.result] as? String)?.split(separator: "`", omittingEmptySubsequences: false)
                if let parts, parts.count > 2, !parts[1].isEmpty { name = String(parts[1]) }
            default:
                continue
            }
        }
        guard let id, !id.isEmpty else { return nil }
        return Model(id: id, name: name ?? id)
    }

    private static let timeout: TimeInterval = 30
    private static let defaultsKey = "claude.defaultModel"

    private enum Key {
        static let id = "id"
        static let name = "name"
        static let type = "type"
        static let subtype = "subtype"
        static let model = "model"
        static let result = "result"
    }
}
