import Foundation

/// The models a provider will start a new session on, the effort each of them
/// will start at, and the model it is set to start them on now.
struct ModelMenu: Equatable {

    /// One entry of the menu.
    ///
    /// `nil` is the provider's own choice, which is what an unset configuration
    /// means — and not the same as naming the model that choice resolves to
    /// today, because that one changes underneath you with the next release.
    struct Option: Identifiable, Equatable {
        let id: String?
        let title: String

        /// The effort levels this model can be started at, `nil` when the
        /// provider gives no way to choose one for it: the entry is then a
        /// model and nothing more.
        var levels: [String]?

        /// The level set for this model, `nil` for its own default.
        var effort: String?

        /// Where Claude Code files the level of this entry, which is the model
        /// itself unless the entry is the provider's choice. Unused by Codex,
        /// which keeps one level for every model.
        var effortKey: String?
    }

    let options: [Option]
    let current: String?

    /// Said under the menu when something outside the settings it writes
    /// decides the model or the effort anyway, which leaves a choice made here
    /// with no effect on the next session. Empty when nothing is in the way.
    let caveats: [String]

    /// Whatever the configuration names is in the menu, listed or not: a model
    /// set by hand, or one from a lineup this app has not heard of, is still
    /// what new sessions will run, and a menu without it would be reporting
    /// something else as the setting.
    init(options: [Option], current: String?, caveats: [String] = []) {
        self.current = current
        self.caveats = caveats
        guard let current, !options.contains(where: { $0.id == current }) else {
            self.options = options
            return
        }
        self.options = options + [Option(id: current, title: current)]
    }

    var currentOption: Option? {
        options.first { $0.id == current }
    }

    /// The same menu with another model and level chosen. Codex keeps one
    /// level for every model, so there `sharedEffort` moves it on all of them.
    /// An entry without levels chooses a model and leaves every level alone.
    func choosing(_ option: Option, effort: String?, sharedEffort: Bool) -> ModelMenu {
        let options = options.map { entry in
            var entry = entry
            if option.levels != nil, entry.levels != nil, sharedEffort || entry.id == option.id { entry.effort = effort }
            return entry
        }
        return ModelMenu(options: options, current: option.id, caveats: caveats)
    }

    /// Both CLIs name their levels with the same words, so one set of titles
    /// serves the two. A level neither has named yet is shown as it is written.
    static func title(ofLevel level: String) -> String {
        switch level {
        case "none": String(localized: "None", comment: "Reasoning effort level")
        case "minimal": String(localized: "Minimal", comment: "Reasoning effort level")
        case "low": String(localized: "Low", comment: "Reasoning effort level")
        case "medium": String(localized: "Medium", comment: "Reasoning effort level")
        case "high": String(localized: "High", comment: "Reasoning effort level")
        case "xhigh": String(localized: "Extra High", comment: "Reasoning effort level, above High")
        case "max": String(localized: "Max", comment: "Reasoning effort level, the highest there is")
        default: level
        }
    }
}
