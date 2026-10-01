import SwiftUI

struct SettingsView: View {

    @Environment(Preferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    /// Unknown until `onAppear`: reading the status touches the file system, and
    /// this view is built again with every menu bar title.
    @State private var bridge: StatusLineBridge.Status?
    @State private var bridgeFailure: String?

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Picker("Track", selection: $preferences.format.window) {
                    ForEach(MenuBarFormat.WindowKind.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                Picker("Percentage", selection: $preferences.format.value) {
                    ForEach(MenuBarFormat.ValueKind.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Toggle("Time until reset", isOn: $preferences.format.showsCountdown)
                Toggle("Window label", isOn: $preferences.format.showsWindowLabel)
                Toggle("Icon", isOn: $preferences.format.showsIcon)
                Toggle("Compact", isOn: $preferences.format.isCompact)
                Toggle("Separator dot", isOn: $preferences.format.showsSeparator)
            } header: {
                Text("Menu bar")
            } footer: {
                HStack(spacing: 6) {
                    Text("Preview:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    // The very image the menu bar is given, so the preview is
                    // the thing itself rather than a likeness of it.
                    Image(nsImage: MenuBarTitle.image(
                        [.init(
                            tint: preferences.format.showsIcon ? UsageProvider.claude.tint : nil,
                            text: preferences.format.text(for: Self.preview, now: .now)
                        )],
                        compact: preferences.format.isCompact,
                        dark: colorScheme == .dark
                    ))
                }
            }

            Section {
                LabeledContent("Status line") {
                    switch bridge {
                    case .installed?:
                        HStack(spacing: 8) {
                            Text("Installed")
                            Button("Remove") { uninstall() }
                        }
                    case .missing?, .foreign?:
                        HStack(spacing: 8) {
                            Text("Not installed")
                            Button("Install") { install() }
                        }
                    case nil:
                        EmptyView()
                    }
                }
                if case .foreign(let command)? = bridge {
                    Text("Currently: \(command)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let bridgeFailure {
                    Text(bridgeFailure)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Launch at login", isOn: $preferences.launchesAtLogin)
                if let failure = preferences.loginItemFailure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leeway asks Claude Code for the counters every five minutes, by running its own /usage report. It spends no usage and needs nothing installed.")
                    Text("The hook adds what that report cannot give: the limits as they arrive with every response of a running session, and the model answering it.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { bridge = StatusLineBridge.status() }
    }

    /// Stand-in reading so the preview shows a realistic title.
    private static let preview = UsageSnapshot(
        fiveHour: .init(usedPercentage: 63, resetsAt: .now.addingTimeInterval(134 * 60)),
        sevenDay: .init(usedPercentage: 41, resetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60)),
        modelName: nil,
        modelID: nil,
        capturedAt: .now
    )

    private func install() {
        run { try StatusLineBridge.install() }
    }

    private func uninstall() {
        run { try StatusLineBridge.uninstall() }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            bridgeFailure = nil
        } catch {
            bridgeFailure = error.localizedDescription
        }
        bridge = StatusLineBridge.status()
    }
}
