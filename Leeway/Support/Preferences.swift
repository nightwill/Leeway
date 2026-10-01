import Foundation
import Observation
import ServiceManagement

/// User-facing settings, persisted in `UserDefaults`.
@MainActor
@Observable
final class Preferences {

    var selection: UsageSelection {
        didSet { defaults.set(selection.rawValue, forKey: Key.selection) }
    }

    var format: MenuBarFormat {
        didSet { store() }
    }

    var launchesAtLogin: Bool {
        didSet { updateLoginItem() }
    }

    /// Set when registering the login item failed — unsigned builds cannot.
    private(set) var loginItemFailure: String?

    private let defaults: UserDefaults
    private var isUpdatingLoginItem = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Key.selection).flatMap(UsageSelection.init(rawValue:)) ?? .claude

        var format = MenuBarFormat()
        if let window = defaults.string(forKey: Key.window).flatMap(MenuBarFormat.WindowKind.init(rawValue:)) {
            format.window = window
        }
        if let value = defaults.string(forKey: Key.value).flatMap(MenuBarFormat.ValueKind.init(rawValue:)) {
            format.value = value
        }
        format.showsCountdown = defaults.object(forKey: Key.countdown) as? Bool ?? format.showsCountdown
        format.showsWindowLabel = defaults.object(forKey: Key.windowLabel) as? Bool ?? format.showsWindowLabel
        format.showsIcon = defaults.object(forKey: Key.icon) as? Bool ?? format.showsIcon
        format.isCompact = defaults.object(forKey: Key.compact) as? Bool ?? format.isCompact
        format.showsSeparator = defaults.object(forKey: Key.separator) as? Bool ?? format.showsSeparator
        self.format = format

        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Key {
        // Named for what it used to hold. The two provider cases kept their
        // raw values, so a choice made before there was a third one still reads.
        static let selection = "bar.provider"
        static let window = "bar.window"
        static let value = "bar.value"
        static let countdown = "bar.countdown"
        static let windowLabel = "bar.windowLabel"
        static let icon = "bar.icon"
        static let compact = "bar.compact"
        static let separator = "bar.separator"
    }

    private func store() {
        defaults.set(format.window.rawValue, forKey: Key.window)
        defaults.set(format.value.rawValue, forKey: Key.value)
        defaults.set(format.showsCountdown, forKey: Key.countdown)
        defaults.set(format.showsWindowLabel, forKey: Key.windowLabel)
        defaults.set(format.showsIcon, forKey: Key.icon)
        defaults.set(format.isCompact, forKey: Key.compact)
        defaults.set(format.showsSeparator, forKey: Key.separator)
    }

    private func updateLoginItem() {
        guard !isUpdatingLoginItem else { return }
        isUpdatingLoginItem = true
        defer { isUpdatingLoginItem = false }

        do {
            if launchesAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemFailure = nil
        } catch {
            loginItemFailure = error.localizedDescription
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
