import Foundation

/// One reading of subscription limits. Claude Code's status-line JSON can be
/// decoded directly; command readers adapt their reports to the same windows.
struct UsageSnapshot: Equatable {

    /// A single rolling limit window.
    struct Window: Equatable {
        let usedPercentage: Double
        let resetsAt: Date

        /// Time left before the window rolls over, `nil` once it has passed.
        func timeLeft(at now: Date) -> TimeInterval? {
            let left = resetsAt.timeIntervalSince(now)
            return left > 0 ? left : nil
        }

        /// Whether the reset stamp has passed, which makes the reading void: the
        /// spend it reports belongs to a window that no longer exists.
        func hasRolledOver(at now: Date) -> Bool {
            timeLeft(at: now) == nil
        }

        /// How much of the window is spent, `nil` once it has rolled over.
        ///
        /// The window that replaced this one starts empty, but only a fresh
        /// reading can say how much of it is gone already — and a reading of a
        /// window that has since rolled over is by definition not that. Calling
        /// it zero reads as "nothing spent" when the truth is "no longer known".
        func usedPercentage(at now: Date) -> Double? {
            hasRolledOver(at: now) ? nil : min(100, max(0, usedPercentage))
        }

        func remainingPercentage(at now: Date) -> Double? {
            usedPercentage(at: now).map { 100 - $0 }
        }

        /// Whether this reading is the later of the two.
        ///
        /// The payload carries no timestamp of its own, so the numbers have to
        /// say it: inside one window the spend only grows, so the higher
        /// percentage is the later reading, and a `resetsAt` further out means a
        /// new window that replaces the old one whatever the percentages are.
        func isLater(than other: Window) -> Bool {
            if resetsAt > other.resetsAt + Self.sameWindowSlack { return true }
            if other.resetsAt > resetsAt + Self.sameWindowSlack { return false }
            return usedPercentage >= other.usedPercentage - Self.roundingSlack
        }

        /// Whether both readings describe the same window rather than one that
        /// has replaced the other.
        func isSameWindow(as other: Window) -> Bool {
            abs(resetsAt.timeIntervalSince(other.resetsAt)) <= Self.sameWindowSlack
        }

        /// The same window with the finer of the two figures for its spend.
        ///
        /// `/usage` prints whole percents where the status line carries
        /// fractions, so a reading taken now can report less of a known window
        /// spent without being behind it. What such a reading brings is that the
        /// window still stands; the figure to show is the higher one.
        func raised(to other: Window) -> Window {
            guard isSameWindow(as: other), other.usedPercentage > usedPercentage else { return self }
            return Window(usedPercentage: other.usedPercentage, resetsAt: resetsAt)
        }

        /// Reset stamps of one window repeat exactly, so the slack only absorbs
        /// a boundary the server rounds differently between responses.
        private static let sameWindowSlack: TimeInterval = 60

        /// A spend this far below what is known is the same figure written
        /// coarser rather than an older one, and a reading dismissed as older is
        /// a reading that never moves the stamp on the panel.
        private static let roundingSlack: Double = 1
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let modelName: String?

    /// The id of that model as Claude Code names it, which is what a setting
    /// kept per model is filed under.
    let modelID: String?

    /// When the state as a whole was last taken — no window shown is older than
    /// this, and none of them is any fresher.
    let capturedAt: Date

    var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil
    }

    func window(_ kind: MenuBarFormat.WindowKind) -> Window? {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }

    /// Folds a newly taken reading into this one, window by window.
    ///
    /// Every Claude Code session writes the same file, and a session that has
    /// been idle reports the limits as they stood when it last heard from the
    /// server. Its status line can land after a fresher one and take the
    /// percentage back down, so a reading that is behind what is already known
    /// is dropped instead of shown.
    func merging(_ reading: UsageSnapshot) -> UsageSnapshot {
        let fiveHour = Self.later(reading.fiveHour, than: self.fiveHour)
        let sevenDay = Self.later(reading.sevenDay, than: self.sevenDay)
        // One stamp stands for both windows, so it only moves when the reading
        // is behind on none of them: a fold that kept an older window is no
        // fresher than that window. A window the reading does not carry says
        // nothing either way — the endpoint reports no five-hour window at all
        // once a session has gone quiet, and treating that as a loss froze the
        // stamp for as long as the quiet lasted.
        let carriesWindow = reading.fiveHour != nil || reading.sevenDay != nil
        let current = Self.isCurrent(reading.fiveHour, against: self.fiveHour)
            && Self.isCurrent(reading.sevenDay, against: self.sevenDay)

        return UsageSnapshot(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            modelName: reading.modelName ?? modelName,
            modelID: reading.modelID ?? modelID,
            capturedAt: carriesWindow && current ? reading.capturedAt : capturedAt
        )
    }

    /// Whether the reading is abreast of what is known about one window —
    /// vacuously so when either side has nothing to say about it.
    ///
    /// Asked of the folded window instead, this would answer no whenever the
    /// fold had to raise a coarse reading to the figure already known, which is
    /// the ordinary case rather than a stale one.
    private static func isCurrent(_ reading: Window?, against known: Window?) -> Bool {
        guard let reading, let known else { return true }
        return reading.isLater(than: known)
    }

    private static func later(_ reading: Window?, than known: Window?) -> Window? {
        guard let reading else { return known }
        guard let known else { return reading }
        return reading.isLater(than: known) ? reading.raised(to: known) : known
    }
}

/// The subset of the `statusLine` JSON that Leeway reads.
private struct StatusLinePayload: Decodable {
    let rateLimits: RateLimitsPayload?
    let model: ModelPayload?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
        case model
    }
}

private struct RateLimitsPayload: Decodable {
    let fiveHour: UsageSnapshot.Window?
    let sevenDay: UsageSnapshot.Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ModelPayload: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

extension UsageSnapshot {

    init(data: Data, capturedAt: Date) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(StatusLinePayload.self, from: data)

        self.init(
            fiveHour: payload.rateLimits?.fiveHour,
            sevenDay: payload.rateLimits?.sevenDay,
            modelName: payload.model?.displayName,
            modelID: payload.model?.id,
            capturedAt: capturedAt
        )
    }
}

extension UsageSnapshot.Window: Decodable {

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
