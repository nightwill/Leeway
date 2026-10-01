import Foundation

/// Reads the limits by asking Claude Code to report them: `claude -p "/usage"`
/// prints what its own `/usage` view shows, and costs nothing to ask — it runs
/// no turn, so no usage is spent finding out how much has been.
///
/// It also asks nothing of this app. The CLI signs the request with its own
/// credentials and refreshes them when they have expired, which is work only it
/// can do unprompted: those credentials sit in keychain items written by the
/// CLI, and an app reading an item it did not write is an app that puts a
/// password dialog on screen every time the owning client rewrites it.
///
/// The price is that the answer is written for a person. The numbers have to be
/// picked out of prose, and prose can be reworded by any release, so a report
/// this code cannot follow is said to be unreadable rather than guessed at.
enum UsageCommand {

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "Claude Code reported the limits in a form Leeway does not recognise.")
            }
        }
    }

    static func read() async throws -> UsageSnapshot {
        // A run that persists its session writes a transcript into the user's
        // own sessions, and these are taken every few minutes for as long as
        // the app runs. Nothing here is ever resumed, so nothing is kept.
        let arguments = ["--print", "--no-session-persistence", "/usage"]
        let output = try await ClaudeCommand.run(arguments, timeout: timeout)
        return try snapshot(from: output, now: .now)
    }

    /// The lines that carry numbers, picked out by the words introducing them:
    ///
    ///     Current session: 30% used · resets Aug 29 at 3pm (Europe/Lisbon)
    ///     Current week (all models): 80% used · resets Aug 30 at 12am (Europe/Lisbon)
    ///
    /// The report carries a `Current week (<model>)` line for each model too.
    /// Those are limits of their own rather than a share of the weekly total,
    /// and the panel has never shown them.
    static func snapshot(from output: String, now: Date) throws -> UsageSnapshot {
        var fiveHour: UsageSnapshot.Window?
        var sevenDay: UsageSnapshot.Window?

        for line in output.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if let reading = value(line, after: fiveHourLabel) {
                fiveHour = window(from: reading, now: now)
            } else if let reading = value(line, after: sevenDayLabel) {
                sevenDay = window(from: reading, now: now)
            }
        }

        let snapshot = UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, modelName: nil, modelID: nil, capturedAt: now)
        // A report with no window in it is what an account with nothing spent
        // looks like: neither limit line is printed until a window has been
        // opened, and both are gone again once they roll over. Only a report
        // that does state a limit this code then fails to read is one that no
        // longer says what it is read for — the mark is the figure itself,
        // which appears nowhere else in the report.
        guard !snapshot.isEmpty || !output.contains(usedMark) else { throw Failure.unreadable }
        return snapshot
    }

    /// A second is all it takes, and the rest of the allowance is for a slow
    /// answer rather than a stalled one.
    private static let timeout: TimeInterval = 30

    private static let fiveHourLabel = "Current session:" // swiftlint:disable:this non_localized_string
    private static let sevenDayLabel = "Current week (all models):" // swiftlint:disable:this non_localized_string
    private static let usedMark = "% used" // swiftlint:disable:this non_localized_string
    private static let resetsMark = "resets " // swiftlint:disable:this non_localized_string

    /// A reset already behind us by this much belongs to a year that has turned
    /// rather than to a window that has just rolled over.
    private static let yearSlack: TimeInterval = 24 * 60 * 60

    private static func value(_ line: String, after label: String) -> String? {
        guard line.hasPrefix(label) else { return nil }
        return String(line.dropFirst(label.count))
    }

    private static func window(from reading: String, now: Date) -> UsageSnapshot.Window? {
        // A limit with no reset named does not apply to this account — the same
        // thing the endpoint used to say by leaving the stamp out.
        guard let usedPercentage = percentage(in: reading),
              let resetsAt = resetDate(in: reading, now: now) else { return nil }
        return UsageSnapshot.Window(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    private static func percentage(in reading: String) -> Double? {
        guard let mark = reading.range(of: usedMark) else { return nil }
        return Double(reading[..<mark.lowerBound].trimmingCharacters(in: .whitespaces))
    }

    private static func resetDate(in reading: String, now: Date) -> Date? {
        guard let mark = reading.range(of: resetsMark) else { return nil }
        var stamp = reading[mark.upperBound...].trimmingCharacters(in: .whitespaces)

        // The zone comes named in brackets after the time. Without one the
        // report is talking about where this machine is.
        var timeZone = TimeZone.current
        if let open = stamp.lastIndex(of: "("), let close = stamp.lastIndex(of: ")"), open < close {
            let name = String(stamp[stamp.index(after: open)..<close])
            if let named = TimeZone(identifier: name) { timeZone = named }
            stamp = String(stamp[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return date(stamp, in: timeZone, now: now)
    }

    /// `Aug 29 at 3pm`, and with minutes when there are any worth showing.
    ///
    /// The year is never printed, so it is taken to be the one that puts the
    /// reset where a reset can be — ahead of now. The last days of December name
    /// a boundary in January, which is the only case where that is not simply
    /// the current year.
    private static func date(_ stamp: String, in timeZone: TimeZone, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        // The report writes them in lower case and the formatter matches exactly.
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"

        // swiftlint:disable:next non_localized_string
        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: stamp) else { continue }

            // Read back in the report's own zone, the parts are the ones it
            // printed; the year the formatter filled in for itself is not.
            var components = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            components.year = calendar.component(.year, from: now)
            guard let candidate = calendar.date(from: components) else { continue }
            if candidate >= now - yearSlack { return candidate }

            components.year = components.year.map { $0 + 1 }
            return calendar.date(from: components)
        }
        return nil
    }
}
