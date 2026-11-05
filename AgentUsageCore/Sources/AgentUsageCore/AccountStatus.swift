import Foundation

/// The status shown in an Account's menu row (§6.2) and its widget.
public enum AccountStatus: Hashable, Sendable {
    case ok
    case stale
    case signInRequired
    case reauthoriseBy(Date)
}

public enum StatusRules {
    /// A Snapshot older than this is Stale (R4).
    public static let staleAfter: TimeInterval = 30 * 60
    /// `Re-authorise by <date>` shows from this long before expiry (U3).
    public static let reauthoriseWarning: TimeInterval = 7 * 24 * 60 * 60
    /// Stale when there's no Snapshot yet, it's more than 30 minutes old (R4), or one of
    /// its reset times has passed, until the next successful fetch (§10).
    public static func isStale(_ snapshot: UsageSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return true }
        if now.timeIntervalSince(snapshot.fetchedAt) > staleAfter { return true }
        return snapshot.limits.contains { limit in
            guard let resetsAt = limit.resetsAt else { return false }
            return resetsAt <= now
        }
    }

    public static func reauthoriseBy(expiresAt: Date?, now: Date) -> Date? {
        guard let expiresAt, now >= expiresAt.addingTimeInterval(-reauthoriseWarning) else { return nil }
        return expiresAt
    }

    /// The single status for a menu row, most urgent first.
    public static func status(of account: PublishedAccount, now: Date) -> AccountStatus {
        if account.signInRequired { return .signInRequired }
        if let date = reauthoriseBy(expiresAt: account.authorisationExpiresAt, now: now) { return .reauthoriseBy(date) }
        if isStale(account.snapshot, now: now) { return .stale }
        return .ok
    }
}
