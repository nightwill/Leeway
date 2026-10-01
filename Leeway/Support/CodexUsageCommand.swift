import Foundation

/// Reads subscription quotas over the CLI's app-server. Codex owns
/// authentication; this client neither reads credentials nor starts a model turn.
enum CodexUsageCommand {

    /// The CLI's own failures, which a reading raises as much as a run does.
    typealias Failure = CodexCommand.Failure

    static func read() async throws -> UsageSnapshot {
        try await CodexAppServer.session { try limits(over: &$0) }
    }

    /// The explicit executable also lets the protocol be checked against a fixture server.
    static func read(executable: URL, environment: [String: String], timeout: TimeInterval = CodexAppServer.defaultTimeout) throws -> UsageSnapshot {
        try CodexAppServer.run(executable: executable, environment: environment, timeout: timeout) { try limits(over: &$0) }
    }

    /// Asks an open server for the account's quotas.
    private static func limits(over connection: inout CodexAppServer.Connection) throws -> UsageSnapshot {
        let account = try connection.request("account/read", params: ["refreshToken": false])
        guard let details = account["account"] as? [String: Any] else { throw Failure.signInRequired }
        guard details["type"] as? String == "chatgpt" else { throw Failure.subscriptionRequired }
        let limits = try connection.request("account/rateLimits/read")
        return try snapshot(from: JSONSerialization.data(withJSONObject: limits), now: .now)
    }

    static func snapshot(from data: Data, now: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(LimitsResponse.self, from: data)
        // Other buckets can be model-specific. Never present one as the account quota.
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        guard let limits, limits.limitId == nil || limits.limitId == "codex" else { throw Failure.unreadable }
        var fiveHour: UsageSnapshot.Window?
        var sevenDay: UsageSnapshot.Window?
        for window in [limits.primary, limits.secondary].compactMap({ $0 }) {
            guard window.usedPercent.isFinite, window.resetsAt?.isFinite != false else { throw Failure.unreadable }
            guard let reset = window.resetsAt else { continue }
            let resetsAt = Date(timeIntervalSince1970: reset)
            guard isAnchored(window, resetsAt: resetsAt, now: now) else { continue }
            let value = UsageSnapshot.Window(usedPercentage: window.usedPercent, resetsAt: resetsAt)
            switch window.windowDurationMins {
            case 300: fiveHour = value
            case 10_080: sevenDay = value
            default: throw Failure.unsupportedWindows
            }
        }
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, modelName: nil, modelID: nil, capturedAt: now)
    }

    /// Whether a request has anchored this window, or it is the empty one the
    /// account is answered with while nothing has been asked of it yet.
    ///
    /// Codex has no way of saying "no window at all". With nothing spent since
    /// the last reset it reports a window dated a full length ahead of whenever
    /// it is asked, so the stamp moves along with the clock and the panel reads
    /// a quiet account as one five hours into a window it never opened — with
    /// the button that would open one greyed out for being redundant.
    ///
    /// A window becomes real when a request anchors it, which is the moment the
    /// stamp stops moving. One reading cannot watch it move, but it does not
    /// have to: a stamp that is still a full window away has nothing behind it.
    private static func isAnchored(_ window: Window, resetsAt: Date, now: Date) -> Bool {
        guard let minutes = window.windowDurationMins else { return true }
        // Spending is the plainer proof of the two, and the only one left in the
        // seconds after a turn, while the stamp it set is still nearly whole.
        if window.usedPercent > 0 { return true }
        return resetsAt.timeIntervalSince(now) <= Double(minutes) * 60 - anchorSlack
    }

    /// What the anchor test has to allow for the reading's own latency: the
    /// stamp is stamped a moment before it is read, so an untouched window
    /// arrives a second or two short of its full length rather than exact. Every
    /// second of this is a second of a real window that is still being called
    /// empty, so it buys only what it must.
    private static let anchorSlack: TimeInterval = 15

    private struct LimitsResponse: Decodable {
        let rateLimits: Limits?
        let rateLimitsByLimitId: [String: Limits]?
    }

    private struct Limits: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?
    }
}
