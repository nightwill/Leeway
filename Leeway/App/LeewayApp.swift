import SwiftUI

@main
struct LeewayApp: App {

    @State private var preferences = Preferences()
    @State private var claudeMonitor = UsageMonitor(provider: .claude)
    @State private var codexMonitor = UsageMonitor(provider: .codex)

    /// The monitors the selection asks for, in the order the panel stacks them.
    private var selected: [UsageMonitor] {
        preferences.selection.providers.map { $0 == .claude ? claudeMonitor : codexMonitor }
    }

    init() {
        // Which directory Claude Code keeps its things in, and whether the
        // environment names a model of its own, are both said in a shell
        // profile — and a menu bar app is opened from Finder, where no profile
        // has been read. Asking the login shell costs a shell start-up, so the
        // app opens on the answers it remembers and corrects itself a moment
        // later: the file it watches, the runs it starts and the panel's model
        // menu all read them afresh.
        Task.detached(priority: .utility) {
            ClaudeDirectory.refreshConfiguredPath()
            ClaudeModelSetting.refreshEnvironmentModel()
            ClaudeEffortSetting.refreshEnvironmentLevel()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsageView(monitors: selected)
                .environment(preferences)
                .id(preferences.selection)
        } label: {
            MenuBarLabel(monitors: selected, format: preferences.format)
                .task(id: preferences.selection) {
                    let showing = selected
                    for monitor in [claudeMonitor, codexMonitor] {
                        monitor.setShowing(showing.contains { $0 === monitor })
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(preferences)
        }
    }
}
