import SwiftUI

/// One provider's block in the panel: both of its limit windows, what it has to
/// say instead when there is no reading yet, and the button that opens a window.
struct UsageProviderSection: View {

    let monitor: UsageMonitor

    /// Set when the panel is showing more than one provider, where a block that
    /// does not name itself is a set of figures belonging to nobody.
    let showsName: Bool

    /// Unknown until `onAppear`: reading the status touches the file system, and
    /// this view is built again every time the menu bar title changes.
    @State private var bridge: StatusLineBridge.Status?
    @State private var bridgeFailure: String?

    /// Unknown until the menu has been read, which for Codex means running its
    /// CLI. Nothing is offered until then: an empty menu invites a choice that
    /// would be made against a list of one.
    @State private var models: ModelMenu?
    @State private var modelFailure: String?
    @State private var isStartingWindow = false
    @State private var windowStartMessage: String?
    @State private var windowStartFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = monitor.snapshot, !snapshot.isEmpty {
                UsageWindowRow(kind: .fiveHour, window: snapshot.fiveHour, now: monitor.now)
                UsageWindowRow(kind: .sevenDay, window: snapshot.sevenDay, now: monitor.now)
            } else {
                waiting
            }

            modelPicker

            windowStarter

            // A state file that cannot be read is reported either way: with no
            // reading it explains the wait, and with an older one it explains
            // why the age keeps growing.
            if let failure = monitor.failure {
                message(failure, failed: true)
            }

            // A failed direct read is worth saying with a reading on screen as
            // much as without one: it is the reason that reading is the last
            // there will be.
            if let failure = monitor.readingFailure {
                message(failure, failed: true)
            }
        }
        .onAppear {
            if monitor.provider == .claude { bridge = StatusLineBridge.status() }
            monitor.refresh()
        }
        .task(id: monitor.snapshot?.modelID) { models = try? await monitor.provider.modelMenu(for: monitor.snapshot) }
    }

    @ViewBuilder
    private var header: some View {
        if showsName || monitor.snapshot?.modelName != nil {
            HStack(alignment: .firstTextBaseline) {
                if showsName {
                    Text(monitor.provider.title)
                        .font(.callout.weight(.semibold))
                }
                Spacer()
                if let model = monitor.snapshot?.modelName {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Set when the hook is not in place and the panel can offer to put it
    /// there. Unknown is not an offer: the status is read a moment after the
    /// panel opens, and an offer that appears late reads as one that appeared
    /// because something went wrong.
    private var offersBridge: Bool {
        switch bridge {
        case .missing?, .foreign?: true
        case .installed?, nil: false
        }
    }

    @ViewBuilder
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch monitor.provider {
            case .codex:
                if monitor.readingFailure == nil {
                    Text(monitor.snapshot == nil
                         ? String(localized: "Reading your Codex limits…")
                         : String(localized: "Codex has no active quota windows to show."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .claude:
                Text("Waiting for the first reading from Claude Code.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // The hook is an offer, not a requirement: the counters arrive
                // without it. Saying what it adds is the whole of the case for
                // installing it.
                if offersBridge {
                    Text("The optional status line hook adds the limits as they arrive with every response of a running session, and the name of the model answering.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if case .foreign(let command)? = bridge {
                        Text("Your current status line will keep running behind it: \(command)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Install status line hook") { install() }
                }
            }

            if let bridgeFailure {
                message(bridgeFailure, failed: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The model new sessions will start on, and the effort they start at: one
    /// menu, each model a submenu of its levels, since a level is always the
    /// level of some model. A provider whose configuration could not be read
    /// shows nothing rather than an empty menu: the panel already carries a
    /// line saying why, and a second one would be the same news in a place
    /// made for a choice.
    @ViewBuilder
    private var modelPicker: some View {
        if let models {
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent("Model") {
                    Menu {
                        ForEach(models.options) { option in
                            modelEntry(option, current: models.current)
                        }
                    } label: {
                        Text(summary(of: models))
                    }
                    .fixedSize()
                }
                .help(Text("New sessions start on this model and effort. A session already running keeps the ones it has.", comment: "Tooltip for the model and effort menu in the panel"))

                ForEach(models.caveats, id: \.self) { caveat in
                    message(caveat, failed: false)
                }

                if let modelFailure {
                    message(modelFailure, failed: true)
                }
            }
        }
    }

    /// A model with levels is a submenu of them, headed by the model's own
    /// default; one without is a plain entry. Toggles rather than a picker,
    /// because a picker ignores a click on the level already ticked, and that
    /// click on another model's submenu is how the model is switched.
    @ViewBuilder
    private func modelEntry(_ option: ModelMenu.Option, current: String?) -> some View {
        let isCurrent = option.id == current
        if let levels = option.levels {
            Menu(isCurrent ? String(localized: "\(option.title) (current)", comment: "Model entry in the menu that new sessions start on") : option.title) {
                ForEach([nil] + levels.map(Optional.some), id: \.self) { level in
                    Toggle(level.map(ModelMenu.title(ofLevel:)) ?? String(localized: "Default", comment: "Effort level: the model's own default"),
                           isOn: Binding(get: { isCurrent && option.effort == level }, set: { _ in select(option, effort: level) }))
                }
            }
        } else {
            Toggle(option.title, isOn: Binding(get: { isCurrent }, set: { _ in select(option, effort: option.effort) }))
        }
    }

    /// The menu's face: the model, then its level where one is set.
    private func summary(of models: ModelMenu) -> String {
        let option = models.currentOption
        let model = option?.title ?? String(localized: "Default")
        guard let effort = option?.effort else { return model }
        return String(localized: "\(model) · \(ModelMenu.title(ofLevel: effort))", comment: "Model and effort level new sessions start at, e.g. Opus · High")
    }

    private var windowStarter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: startFiveHourWindow) {
                HStack(spacing: 6) {
                    if isStartingWindow {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting 5-hour window…")
                    } else if monitor.isFiveHourWindowOpen {
                        Text("5-hour window is active")
                    } else {
                        Text("Start 5-hour window")
                    }
                }
            }
            .disabled(isStartingWindow || monitor.isFiveHourWindowOpen)
            .help(monitor.provider.windowStarterHint)

            // A button greyed out with nothing beside it reads as a broken
            // button, and the reason it is off is a window somebody opened
            // rather than a state of the app. Saying when it was opened is what
            // settles that: a window nobody remembers starting was started by a
            // turn they took themselves, and the clock time is what places it.
            if let opened = windowOpenedAt {
                Text("Opened at \(opened.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let windowStartMessage {
                message(windowStartMessage, failed: windowStartFailed)
            }
        }
        // The confirmation is given a few seconds; the ordinary cadence has all
        // the time it needs. A window it brings in answers the complaint that
        // none could be confirmed, and leaving that complaint under a button
        // now reading "active" is the contradiction the complaint was there to
        // end, the other way round.
        .onChange(of: monitor.isFiveHourWindowOpen) { _, isOpen in
            if isOpen, windowStartFailed {
                windowStartMessage = nil
                windowStartFailed = false
            }
        }
    }

    /// When the open five-hour window was anchored: its reset stamp less the
    /// length the window is named for. `nil` when no window is running, where
    /// the button speaks for itself.
    private var windowOpenedAt: Date? {
        guard let window = monitor.snapshot?.fiveHour,
              window.timeLeft(at: monitor.now) != nil else { return nil }
        return window.resetsAt - MenuBarFormat.WindowKind.fiveHour.duration
    }

    private func message(_ text: String, failed: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(failed ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func startFiveHourWindow() {
        isStartingWindow = true
        windowStartMessage = nil
        windowStartFailed = false

        Task {
            do {
                let reported = try await monitor.provider.startWindow()
                // The button stays busy until the reading confirms the window,
                // because until then the panel is still showing the state from
                // before it was pressed and there is nothing to congratulate.
                if await monitor.readOpenedWindow(reported: reported) {
                    windowStartMessage = String(localized: "The window has started.")
                } else if monitor.readingFailure == nil {
                    // A reading that failed has a line of its own below, and it
                    // says more than this one could: the window is then not
                    // unconfirmed but unread, and saying both is saying one
                    // thing twice.
                    windowStartMessage = String(localized: "The request finished, but the five-hour window could not be confirmed.")
                    windowStartFailed = true
                }
            } catch {
                windowStartMessage = error.localizedDescription
                windowStartFailed = true
            }
            isStartingWindow = false
        }
    }

    /// Shows the choice at once and writes it behind that: the menu is the
    /// panel's own reading of the setting, so leaving it on the old model until
    /// the write comes back reads as a menu that ignored the click. A write
    /// that fails puts the setting back where it was and says so.
    private func select(_ option: ModelMenu.Option, effort: String?) {
        let previous = models
        let shared = monitor.provider.sharesEffortAcrossModels
        models = models.map { $0.choosing(option, effort: effort, sharedEffort: shared) }
        modelFailure = nil

        Task {
            do {
                try await monitor.provider.select(option, effort: effort)
            } catch {
                models = previous
                modelFailure = error.localizedDescription
            }
        }
    }

    private func install() {
        do {
            try StatusLineBridge.install()
            bridgeFailure = nil
        } catch {
            bridgeFailure = error.localizedDescription
        }
        bridge = StatusLineBridge.status()
    }
}
