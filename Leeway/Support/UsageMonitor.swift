import Foundation
import Observation

/// Keeps a current reading of the limits from the two sources that have one: the
/// file the bridge script writes, and the CLI's own `/usage` report, which
/// answers with no session running. `now` ticks so countdowns stay live between
/// readings.
@MainActor
@Observable
final class UsageMonitor {

    let provider: UsageProvider

    private(set) var snapshot: UsageSnapshot?
    private(set) var now = Date.now

    /// Set when the state file exists but could not be read or decoded.
    private(set) var failure: String?

    /// Set when the last direct reading failed; cleared by the next one that works.
    private(set) var readingFailure: String?

    private var lastModified: Date?
    private var lastReading: Date?
    private var reading: Task<Void, Never>?

    /// Set when a reading was asked for while one was already under way.
    private var wantsReading = false
    private var readsInBackground: Bool

    /// How long the reading in hand is left to stand before the next one, which
    /// the readings themselves set as the counters move.
    private var readingInterval = UsageMonitor.quietInterval

    init(provider: UsageProvider = .claude) {
        self.provider = provider
        // Nothing is on screen yet, and the selection says which of these ever
        // will be. Until it does, no reading is worth the process it costs.
        readsInBackground = false
        reload()
        // Two cadences, because the two jobs cost differently: looking at the
        // state file is a stat call, while moving `now` redraws every countdown
        // in the panel along with the menu bar title.
        schedule(every: Self.pollInterval) { monitor in
            monitor.reload()
            if monitor.readsInBackground { monitor.read(staleAfter: monitor.readingInterval) }
        }
        schedule(every: Self.clockInterval) { monitor in
            monitor.now = .now
        }
    }

    /// How long ago the reading was taken, `nil` when there is no reading yet.
    var age: TimeInterval? {
        snapshot.map { now.timeIntervalSince($0.capturedAt) }
    }

    /// Whether the panel and the menu bar are showing this provider, which is
    /// what decides whether the loop keeps running: a reading costs a whole
    /// process to take, and one taken for a provider nobody is looking at is
    /// spent on nothing.
    func setShowing(_ isShowing: Bool) {
        readsInBackground = isShowing
        if isShowing { refresh() }
    }

    /// Brings everything up to date for an opening panel: the clock the
    /// countdowns read, the file, and a direct reading unless one was just taken.
    func refresh() {
        now = .now
        reload()
        read(staleAfter: Self.onDemandInterval)
    }

    /// Whether the five-hour window is open, which is both what the countdown
    /// on the panel needs and what the button offering to open one goes by.
    var isFiveHourWindowOpen: Bool {
        snapshot?.fiveHour?.timeLeft(at: now) != nil
    }

    /// Reads until the answer accounts for a five-hour window this app has just
    /// opened. Nothing else will report it: a turn run outside a session leaves
    /// the state file untouched, because the status line only runs for a session
    /// that has one.
    ///
    /// It takes more than one reading because the turn being over is not the
    /// same as the CLI saying so — `/usage` still answers from the state it held
    /// while the turn was in flight, and one reading landing on "no window at
    /// all" leaves the panel saying exactly what it said before the button was
    /// pressed.
    ///
    /// What the starting turn reported, when it reported anything, is folded in
    /// first: it comes straight from the server's answer to that turn, so a
    /// window it carries needs no reading to confirm it.
    func readOpenedWindow(reported: UsageSnapshot?) async -> Bool {
        if let reported {
            absorb(reported)
            if isFiveHourWindowOpen { return true }
        }
        for attempt in 1...Self.openAttempts {
            if attempt > 1 { try? await Task.sleep(for: .seconds(Self.openRetryDelay)) }
            await readingNow()
            if isFiveHourWindowOpen { return true }
        }
        return false
    }

    /// The file costs a stat call to check, and the menu bar should keep up with
    /// a session that is answering.
    private static let pollInterval: TimeInterval = 5

    /// Every value on screen is rounded to minutes, so the clock moves in steps
    /// coarse enough to spare the redraws and fine enough to stay honest.
    private static let clockInterval: TimeInterval = 15

    /// A reading costs a whole process to start, so the loop runs no faster
    /// than the counters ask for — and it is the readings that say how fast
    /// that is. One that finds the spend where it left it doubles the wait up to
    /// the quiet cadence; one that finds it moved brings the next reading in
    /// close, closer still when the step was large enough to be a turn
    /// answering right now.
    private static let quietInterval: TimeInterval = 5 * 60
    private static let movingInterval: TimeInterval = 90
    private static let climbingInterval: TimeInterval = 30

    /// Percentage points between two readings that mark the second as taken
    /// mid-session rather than after it.
    private static let climbThreshold: Double = 1

    /// Readings to spend confirming a window this app has just opened, and the
    /// pause between them. A window that has not appeared by the last of them is
    /// one the ordinary cadence picks up soon enough on its own.
    ///
    /// The pause is what it is because a window is not visibly open the instant
    /// it opens: until the spend registers, the only thing telling it from the
    /// empty window Codex reports for a quiet account is how much of its length
    /// has gone, and that takes a few seconds to become an answer. The last
    /// attempt has to land past it.
    private static let openAttempts = 3
    private static let openRetryDelay: TimeInterval = 8

    /// An opened panel is worth a fresh reading, within reason.
    private static let onDemandInterval: TimeInterval = 20

    private func schedule(every interval: TimeInterval, _ work: @escaping @MainActor (UsageMonitor) -> Void) {
        // The timer keeps itself alive on the run loop and stops once the monitor is gone.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                work(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func reload() {
        guard provider == .claude else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: ClaudeDirectory.stateURL.path)
        guard let modified = attributes?[.modificationDate] as? Date else {
            // No file at all is the state before the first session, not a fault.
            lastModified = nil
            failure = nil
            return
        }
        guard modified != lastModified else { return }

        do {
            let data = try Data(contentsOf: ClaudeDirectory.stateURL)
            absorb(try UsageSnapshot(data: data, capturedAt: modified))
            // Only a reading that worked marks the file as seen. The stamp is the
            // one thing that would tell the next tick to try this file again, so
            // a failure leaves it alone.
            lastModified = modified
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func read(staleAfter interval: TimeInterval) {
        // Not the `now` above: that one is deliberately coarse.
        let now = Date.now
        if let lastReading, now.timeIntervalSince(lastReading) < interval { return }

        guard reading == nil else {
            // The reading under way was launched before whatever asked for this
            // one, so its answer cannot account for it and has to be followed by
            // another. Dropping the request instead left the panel showing the
            // state from before, which is what made the button under a freshly
            // opened window need pressing twice: the answer in flight was the
            // one still reporting no window at all.
            wantsReading = true
            return
        }
        startReading(at: now)
    }

    /// Takes a reading however recent the last one was, and hands back only once
    /// it is in.
    private func readingNow() async {
        read(staleAfter: 0)
        // A request that arrived while a reading was under way runs as a task of
        // its own once that one is done, so the wait goes round again to catch it.
        while let reading { await reading.value }
    }

    private func startReading(at now: Date) {
        lastReading = now
        wantsReading = false

        reading = Task { [weak self] in
            do {
                guard let provider = self?.provider else { return }
                let limits = try await provider.read()
                self?.absorb(limits)
                self?.readingFailure = nil
            } catch {
                self?.readingFailure = error.localizedDescription
            }
            guard let self else { return }
            reading = nil
            if wantsReading { read(staleAfter: 0) }
        }
    }

    /// Any source can be behind what is already known, so readings are folded in
    /// rather than assigned.
    private func absorb(_ reading: UsageSnapshot) {
        let known = snapshot?.fiveHour
        // Codex has one authoritative source. Assign it directly so a quota
        // reset or an account change can lower the counters or remove a window.
        snapshot = provider == .codex ? reading : snapshot?.merging(reading) ?? reading
        pace(from: known, to: snapshot?.fiveHour)
    }

    /// Sets when the next reading falls due from how far this one moved the
    /// five-hour window — the one that answers within a session, where the
    /// weekly window barely stirs.
    private func pace(from known: UsageSnapshot.Window?, to current: UsageSnapshot.Window?) {
        guard let current else { return }
        guard current != known else {
            // Nothing moved, so the cadence that found that out was quicker than
            // it needed to be. Backing off by steps rather than at once keeps up
            // with a pause between two turns.
            readingInterval = min(Self.quietInterval, readingInterval * 2)
            return
        }
        // A window that was not there a moment ago is a session just starting.
        guard let known, current.isSameWindow(as: known) else {
            readingInterval = Self.climbingInterval
            return
        }
        let climb = current.usedPercentage - known.usedPercentage
        readingInterval = climb >= Self.climbThreshold ? Self.climbingInterval : Self.movingInterval
    }
}
