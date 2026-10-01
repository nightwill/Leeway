import SwiftUI

/// One limit window in the panel: how much is spent and when it rolls over.
struct UsageWindowRow: View {

    let kind: MenuBarFormat.WindowKind
    let window: UsageSnapshot.Window?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(kind.title)
                    .font(.callout)
                Spacer()
                Text(usedText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(used == nil ? .secondary : .primary)
            }

            ProgressView(value: (used ?? 0) / 100)
                .progressViewStyle(.linear)
                .tint(tint)

            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// `nil` when there is no reading, or when the one there is describes a
    /// window that has since rolled over.
    private var used: Double? {
        window?.usedPercentage(at: now)
    }

    private var usedText: String {
        used.map { "\(Int($0.rounded()))%" } ?? MenuBarFormat.placeholder
    }

    private var tint: Color {
        switch used {
        case .none: .secondary
        case .some(..<70): .green
        case .some(..<90): .orange
        default: .red
        }
    }

    private var resetText: String {
        guard let window else {
            // Reached only with a reading in hand, so this is the reading
            // saying the window is not running rather than the wait for one.
            return String(localized: "No window running")
        }
        guard let left = window.timeLeft(at: now) else {
            // The window rolled over after the reading was taken, so what the
            // one that replaced it holds is unknown until something reports it.
            return String(localized: "Window has reset · waiting for a reading")
        }
        // Past today the clock alone is ambiguous, and the weekly window needs days.
        let clock = window.resetsAt.formatted(date: left > 20 * 3600 ? .abbreviated : .omitted, time: .shortened)
        return String(localized: "Resets at \(clock) · in \(Self.readable(left))")
    }

    private static func readable(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }
}
