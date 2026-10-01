import SwiftUI

/// The panel behind the menu bar item: the limits of every provider the
/// selection asks for, in full.
struct UsageView: View {

    let monitors: [UsageMonitor]

    @Environment(Preferences.self) private var preferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            selector

            ForEach(Array(monitors.enumerated()), id: \.element.provider) { index, monitor in
                if index > 0 { Divider() }
                UsageProviderSection(monitor: monitor, showsName: monitors.count > 1)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 290)
    }

    private var selector: some View {
        @Bindable var preferences = preferences

        // Segmented rather than a menu: there are three choices and picking
        // between them is the panel's most frequent act, worth one click.
        return Picker("Usage", selection: $preferences.selection) {
            ForEach(UsageSelection.allCases) { selection in
                Text(selection.title).tag(selection)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(freshness)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings…") { showSettings() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    /// The age of the oldest reading on screen, because a panel is as fresh as
    /// the staler half of what it is showing.
    private var freshness: String {
        guard let age = monitors.compactMap(\.age).max() else { return String(localized: "No data yet") }
        guard age > 90 else { return String(localized: "Updated just now") }
        let elapsed = Duration.seconds(age).formatted(.units(allowed: [.hours, .minutes], maximumUnitCount: 1))
        return String(localized: "Updated \(elapsed) ago")
    }

    /// An accessory app has to activate itself, or Settings opens behind everything.
    private func showSettings() {
        NSApplication.shared.activate()
        openSettings()
    }
}
