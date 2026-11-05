import AgentUsageCore
import Foundation

/// Canned published Accounts for previews and the widget placeholder.
/// Every figure here is sample data and is never shown for a real Account.
public enum PreviewData {
    public enum State: String, CaseIterable, Sendable {
        case onPace = "On pace"
        case overPace = "Over pace"
        case stale = "Stale"
        case signInRequired = "Sign in required"
        case reauthoriseBy = "Re-authorise by"
        case limitReached = "Limit reached"
        case noActiveSession = "No active session"
        case noWindowLength = "No Window length"
        case chooseAccount = "Choose an Account"
    }

    private static let hour: TimeInterval = 60 * 60

    public static func account(_ state: State, now: Date = Date()) -> PublishedAccount? {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        func snapshot(_ limits: [LimitUsage], fetchedAgo: TimeInterval = 2 * 60) -> UsageSnapshot {
            UsageSnapshot(accountID: id, limits: limits, fetchedAt: now.addingTimeInterval(-fetchedAgo))
        }
        func session(_ used: Double?, resetIn: TimeInterval?) -> LimitUsage {
            LimitUsage(name: "Session (5h)", percentUsed: used, windowLength: WindowLength.claudeSession, resetsAt: resetIn.map { now.addingTimeInterval($0) })
        }
        func weekly(_ used: Double, resetIn: TimeInterval) -> LimitUsage {
            LimitUsage(name: "Weekly", percentUsed: used, windowLength: WindowLength.claudeWeekly, resetsAt: now.addingTimeInterval(resetIn))
        }
        var account = PublishedAccount(
            id: id, provider: .claude, name: "Work", email: "firstname.lastname@example-company.com",
            snapshot: snapshot([session(45, resetIn: 2 * hour), weekly(40, resetIn: 4 * 24 * hour)])
        )
        switch state {
        case .onPace:
            break
        case .overPace:
            account.snapshot = snapshot([session(66, resetIn: 2 * hour), weekly(71, resetIn: 2.6 * 24 * hour)])
        case .stale:
            account.snapshot = snapshot([session(45, resetIn: 2 * hour), weekly(40, resetIn: 4 * 24 * hour)], fetchedAgo: 42 * 60)
        case .signInRequired:
            account.signInRequired = true
        case .reauthoriseBy:
            account.authorisationExpiresAt = now.addingTimeInterval(5 * 24 * hour)
        case .limitReached:
            account.snapshot = snapshot([session(100, resetIn: 1.25 * hour), weekly(93, resetIn: 1 * 24 * hour)])
        case .noActiveSession:
            account.snapshot = snapshot([session(0, resetIn: nil), weekly(22, resetIn: 5 * 24 * hour)])
        case .noWindowLength:
            account.snapshot = snapshot([
                LimitUsage(name: "Credits", percentUsed: 38, windowLength: nil, resetsAt: now.addingTimeInterval(9 * 24 * hour)),
                session(20, resetIn: 4 * hour),
            ])
        case .chooseAccount:
            return nil
        }
        return account
    }
}
