import Foundation

/// Whose limits the panel and the menu bar title are showing.
///
/// Separate from `UsageProvider` because it is a choice about the display rather
/// than about where a reading comes from: one of its cases asks for every
/// provider at once, and a reading still belongs to exactly one of them.
enum UsageSelection: String, CaseIterable, Identifiable {
    case claude
    case codex
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: String(localized: "Claude")
        case .codex: String(localized: "Codex")
        case .both: String(localized: "Both")
        }
    }

    /// The providers shown, in the order the panel stacks them.
    var providers: [UsageProvider] {
        switch self {
        case .claude: [.claude]
        case .codex: [.codex]
        case .both: UsageProvider.allCases
        }
    }
}
