import AppKit

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: String(localized: "Claude")
        case .codex: String(localized: "Codex")
        }
    }

    /// The colour of the provider's dot in the menu bar, which is what tells
    /// two readings apart in a title carrying both.
    var tint: NSColor {
        switch self {
        case .claude: .systemOrange
        case .codex: .lightGray
        }
    }

    func read() async throws -> UsageSnapshot {
        switch self {
        case .claude: try await UsageCommand.read()
        case .codex: try await CodexUsageCommand.read()
        }
    }

    /// Runs the smallest turn this provider will take, which is the only thing
    /// that opens a five-hour window: both anchor the window to the first
    /// request after the last reset rather than to a clock.
    ///
    /// Hands back the limits the turn itself reported, `nil` when it reported
    /// none and only a reading can tell whether the window opened.
    func startWindow() async throws -> UsageSnapshot? {
        switch self {
        case .claude:
            return try await ClaudeSessionStarter.start()
        case .codex:
            try await CodexSessionStarter.start()
            return nil
        }
    }

    /// The models this provider will start a new session on, the effort each
    /// starts at, and the model it is set to start them on. Nothing here
    /// reaches a session already running: that one keeps what it was started
    /// with until it ends.
    ///
    /// Claude's own choice of model files its level under the model the last
    /// reading named, so the menu is read again when that changes.
    func modelMenu(for snapshot: UsageSnapshot?) async throws -> ModelMenu {
        switch self {
        case .claude: try ClaudeModelSetting.menu(lastModel: snapshot?.modelID)
        case .codex: try await CodexModelCommand.menu()
        }
    }

    /// Sets the model and, for an entry that offers levels, the level it
    /// starts at. An entry without levels leaves the level as it is.
    func select(_ option: ModelMenu.Option, effort: String?) async throws {
        switch self {
        case .claude:
            try ClaudeModelSetting.set(option, effort: effort)
        case .codex:
            if option.levels == nil {
                try await CodexModelCommand.set(option.id)
            } else {
                try await CodexModelCommand.set(option.id, effort: .some(effort))
            }
        }
    }

    /// Codex keeps one level for every model; Claude keeps one per model.
    var sharesEffortAcrossModels: Bool { self == .codex }

    /// What pressing the button is about to spend, which is not the same on both
    /// and is the one thing worth knowing before pressing it.
    var windowStarterHint: String {
        switch self {
        case .claude:
            String(localized: "Sends a minimal Claude Code request using Haiku.")
        case .codex:
            String(localized: "Sends a minimal Codex request, which counts towards the window it opens.")
        }
    }
}
