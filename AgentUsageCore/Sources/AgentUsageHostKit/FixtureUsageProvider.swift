#if DEBUG
import AgentUsageCore
import Foundation

/// Debug-only data source that returns canned Limits and needs no Authorisation (#18).
/// It's compiled out of Release builds; CI checks the Release binary for this type's name.
public struct FixtureUsageProvider: UsageProvider {
    let now: @Sendable () -> Date
    let calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public func fetch(for account: Account) async throws -> UsageSnapshot {
        let now = now()
        let scenario = account.fixtureScenario ?? .normal
        switch scenario {
        case .signInRequired: throw UsageProviderError.authorisationRejected
        case .offline: throw UsageProviderError.network("fixture is offline")
        default: break
        }

        let sessionReset = Self.nextSessionReset(after: now)
        let weeklyReset = Self.nextMonday0900(after: now, calendar: calendar)
        let (session, weekly): (Double, Double) = switch scenario {
        case .overPace: (88, 79)
        case .limitReached: (100, 64)
        case .noActiveSession: (0, 71)
        default: (45, 71)
        }
        return UsageSnapshot(
            accountID: account.id,
            limits: [
                LimitUsage(
                    name: "Session (5h)", percentUsed: session, windowLength: WindowLength.claudeSession,
                    resetsAt: scenario == .noActiveSession ? nil : sessionReset
                ),
                LimitUsage(name: "Weekly", percentUsed: weekly, windowLength: WindowLength.claudeWeekly, resetsAt: weeklyReset),
            ],
            fetchedAt: now
        )
    }

    /// Sessions start on 5-hour boundaries, so the reset is stable between fetches and
    /// the marker visibly moves while the figure stays the same (P5).
    static func nextSessionReset(after now: Date) -> Date {
        let window = WindowLength.claudeSession
        let next = (now.timeIntervalSince1970 / window).rounded(.down) * window + window
        return Date(timeIntervalSince1970: next)
    }

    static func nextMonday0900(after now: Date, calendar: Calendar) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(WindowLength.claudeWeekly)
    }
}
#endif
