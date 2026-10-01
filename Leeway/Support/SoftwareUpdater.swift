import AppKit
import Observation
import Sparkle

/// Sparkle, as the settings window needs it: whether checks run on their own,
/// and a way to ask right now.
///
/// The feed and the public key that every update must be signed with are in
/// `Info.plist`; the private half never leaves the release machine's Keychain.
@MainActor
@Observable
final class SoftwareUpdater {

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    /// False while a check is already under way.
    private(set) var canCheck = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheck = canCheck }
        }
    }

    func checkForUpdates() {
        // A menu bar app is never the active one, and Sparkle's window would
        // open behind whatever is.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
