import Foundation

/// How the usage reading is rendered into the menu bar title.
struct MenuBarFormat: Equatable {

    /// Which rolling limit the menu bar tracks.
    enum WindowKind: String, CaseIterable, Identifiable {
        case fiveHour
        case sevenDay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fiveHour: String(localized: "5-hour session")
            case .sevenDay: String(localized: "7-day window")
            }
        }

        var shortTitle: String {
            switch self {
            case .fiveHour: String(localized: "5h")
            case .sevenDay: String(localized: "7d")
            }
        }

        /// How long the window runs — the one thing its own name already says,
        /// and the only way back from a reset stamp to the moment the window
        /// was anchored. Neither provider reports that moment; both report
        /// where it ends.
        var duration: TimeInterval {
            switch self {
            case .fiveHour: 5 * 3600
            case .sevenDay: 7 * 24 * 3600
            }
        }
    }

    /// Whether the percentage counts what is spent or what is left.
    enum ValueKind: String, CaseIterable, Identifiable {
        case used
        case remaining

        var id: String { rawValue }

        var title: String {
            switch self {
            case .used: String(localized: "Used")
            case .remaining: String(localized: "Remaining")
            }
        }
    }

    var window: WindowKind = .fiveHour
    var value: ValueKind = .used
    var showsCountdown = true
    var showsWindowLabel = false
    var showsIcon = true

    /// Whether the title is drawn in a narrower face, to take less of the menu bar.
    var isCompact = false

    /// Whether the parts of the title are told apart by a dot rather than a space.
    var showsSeparator = true

    /// The menu bar title, e.g. `63% · 2:14`.
    ///
    /// A window whose percentage is no longer known shows the placeholder rather
    /// than a number: the title is the whole of what the menu bar says, and a
    /// stale reading passed off as a figure is worse than no figure.
    func text(for snapshot: UsageSnapshot?, now: Date) -> String {
        guard let window = snapshot?.window(window),
              let percentage = Self.percentage(of: window, value: value, now: now) else {
            return Self.placeholder
        }

        var parts: [String] = []
        if showsWindowLabel {
            parts.append(self.window.shortTitle)
        }
        parts.append(percentage)

        if showsCountdown, let left = window.timeLeft(at: now) {
            parts.append(Self.countdown(left))
        }
        return parts.joined(separator: showsSeparator ? Self.separator : Self.gap)
    }

    static let placeholder = "—"
    private static let separator = " · "
    private static let gap = " "

    private static func percentage(of window: UsageSnapshot.Window, value: ValueKind, now: Date) -> String? {
        let shown = value == .used ? window.usedPercentage(at: now) : window.remainingPercentage(at: now)
        return shown.map { "\(Int($0.rounded()))%" }
    }

    /// `2:14` — hours and minutes left, `0:07` inside the last hour.
    static func countdown(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
