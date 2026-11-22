import SwiftUI

/// What the menu bar item shows: every reading the selection asks for, drawn as
/// one image.
///
/// A view of its own for the one thing a view has and the app does not — the
/// appearance the menu bar is drawing in. It is not the app's: with a light
/// system appearance and a dark desktop picture the menu bar turns dark on its
/// own, and a title drawn in the app's colours comes out black on black.
struct MenuBarLabel: View {

    let monitors: [UsageMonitor]
    let format: MenuBarFormat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: MenuBarTitle.image(readings, compact: format.isCompact, dark: colorScheme == .dark))
    }

    private var readings: [MenuBarTitle.Reading] {
        monitors.map { monitor in
            // The tracked window is one choice for both providers, and a plan
            // without a five-hour limit would show a dash for good under it.
            // Its weekly window is then the only figure there is.
            var format = format
            if !monitor.hasFiveHourLimit { format.window = .sevenDay }
            return MenuBarTitle.Reading(
                tint: format.showsIcon ? monitor.provider.tint : nil,
                text: format.text(for: monitor.snapshot, now: monitor.now)
            )
        }
    }
}
