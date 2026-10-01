import Foundation

/// Starts the smallest practical Claude Code turn so an idle account receives a
/// fresh five-hour usage window without exposing Claude Code's private inference
/// protocol in the app.
enum ClaudeSessionStarter {

    /// Runs the turn and hands back the limits the server answered it with,
    /// `nil` when the run did not report them.
    ///
    /// That answer is what confirms the window. `/usage` asked right after the
    /// turn can still report the account as idle for longer than any wait worth
    /// putting behind a button, while the turn's own response already carries
    /// the window it opened.
    static func start() async throws -> UsageSnapshot? {
        let output = try await ClaudeCommand.run(
            [
                "--print",
                "--model", "haiku",
                "--tools", "",
                "--no-session-persistence",
                "--system-prompt", "Reply with a single period.",
                // Haiku otherwise thinks a couple of hundred tokens over
                // how to answer with a period.
                "--settings", #"{"alwaysThinkingEnabled":false}"#,
                // The rate-limit event only comes out in the streamed form,
                // which the CLI refuses to print without the verbose flag.
                "--output-format", "stream-json",
                "--verbose",
                ".",
            ],
            timeout: timeout
        )
        return limits(in: output, now: .now)
    }

    /// The last rate-limit event in the stream, read as a snapshot.
    ///
    /// The per-window figures are marked internal in the CLI and may go
    /// without notice, so a stream that stops carrying them is no failure:
    /// the window is then confirmed the slow way, by reading `/usage`.
    static func limits(in output: String, now: Date) -> UsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let windows = output
            .split(whereSeparator: \.isNewline)
            .compactMap { try? decoder.decode(StreamEvent.self, from: Data($0.utf8)) }
            .last { $0.type == rateLimitEvent && $0.rateLimitInfo?.unifiedWindows != nil }?
            .rateLimitInfo?.unifiedWindows

        let snapshot = UsageSnapshot(
            fiveHour: windows?.fiveHour?.window,
            sevenDay: windows?.sevenDay?.window,
            modelName: nil,
            modelID: nil,
            capturedAt: now
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    /// The turn itself takes a couple of seconds. The rest of the allowance is
    /// for a slow answer rather than a stalled one, which the deadline ends so
    /// the button is not left spinning for good.
    private static let timeout: TimeInterval = 60

    private static let rateLimitEvent = "rate_limit_event"
}

/// The subset of a `stream-json` line that carries the limits.
private struct StreamEvent: Decodable {
    let type: String
    let rateLimitInfo: RateLimitInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimitInfo = "rate_limit_info"
    }
}

private struct RateLimitInfo: Decodable {
    let unifiedWindows: UnifiedWindows?
}

private struct UnifiedWindows: Decodable {
    let fiveHour: UnifiedWindow?
    let sevenDay: UnifiedWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct UnifiedWindow: Decodable {
    /// A fraction of the limit, where the status line writes a percentage.
    let utilization: Double
    let resetsAt: Date

    var window: UsageSnapshot.Window {
        UsageSnapshot.Window(usedPercentage: utilization * 100, resetsAt: resetsAt)
    }
}
