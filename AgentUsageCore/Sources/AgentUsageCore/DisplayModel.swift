import Foundation

/// Everything a bar needs to be drawn, worked out in the core so the views do no maths.
public struct LimitDisplay: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// `45%`, or `—` when the figure is missing.
    public var percentText: String
    /// How much of the bar is filled, 0–1 (F2).
    public var fillFraction: Double
    /// The Pace marker position, 0–1. `nil` means no marker (P0, P6).
    public var markerFraction: Double?
    public var band: PaceBand
    /// `on pace` / `over +12%` (C5).
    public var paceLabel: String?
    /// The medium widget's line under the bar title: `resets in 2h 14m`,
    /// `Limit reached · resets in 2h 14m` or `No active session`.
    public var detailText: String?
    /// The small widget's shorter text, with no reset time: `Limit reached`, `No active session`.
    public var compactText: String?
    public var isLimitReached: Bool
    public var noActiveSession: Bool
}

/// One Account's widget or menu row.
public struct AccountCard: Hashable, Sendable {
    public var accountID: UUID
    public var providerName: String
    public var providerGlyph: String
    public var accountName: String
    public var email: String
    public var emailVerified: Bool
    /// Up to two, in the Provider's order (§10). Empty when sign-in is required.
    public var limits: [LimitDisplay]
    public var updatedText: String
    public var status: AccountStatus
    /// Dim the bars and show a warning icon (R4).
    public var isStale: Bool
    public var signInRequired: Bool
    /// `Re-authorise by 12 Nov` (U3).
    public var reauthoriseText: String?
    /// No Snapshot has been fetched yet.
    public var awaitingFirstFetch: Bool
}

public enum WidgetContent: Hashable, Sendable {
    /// No Account in this widget's slot: fewer Accounts than its number (§6.1, ADR-0009).
    case chooseAccount
    case account(AccountCard)
}

public enum DisplayModel {
    /// The widget shows at most this many Limits (F1, §10).
    public static let maxLimits = 2

    public static func content(for account: PublishedAccount?, now: Date, calendar: Calendar = .current) -> WidgetContent {
        guard let account else { return .chooseAccount }
        return .account(card(for: account, now: now, calendar: calendar))
    }

    public static func card(for account: PublishedAccount, now: Date, calendar: Calendar = .current) -> AccountCard {
        let status = StatusRules.status(of: account, now: now)
        let limits: [LimitDisplay]
        if account.signInRequired {
            // Never show zeros in place of a refused fetch (R5, R6).
            limits = []
        } else {
            limits = (account.snapshot?.limits ?? [])
                .prefix(maxLimits)
                .enumerated()
                .map { limitDisplay($0.element, id: $0.offset, now: now, calendar: calendar) }
        }
        let reauthoriseText = StatusRules.reauthoriseBy(expiresAt: account.authorisationExpiresAt, now: now)
            .map { UsageFormatting.reauthoriseText($0, calendar: calendar) }

        return AccountCard(
            accountID: account.id,
            providerName: account.provider.displayName,
            providerGlyph: account.provider.glyphSystemName,
            accountName: account.name,
            email: account.email,
            emailVerified: account.emailVerified,
            limits: limits,
            updatedText: UsageFormatting.updatedText(fetchedAt: account.snapshot?.fetchedAt, now: now),
            status: status,
            isStale: account.snapshot != nil && StatusRules.isStale(account.snapshot, now: now),
            signInRequired: account.signInRequired,
            reauthoriseText: reauthoriseText,
            awaitingFirstFetch: account.snapshot == nil && !account.signInRequired
        )
    }

    public static func limitDisplay(_ limit: LimitUsage, id: Int = 0, now: Date, calendar: Calendar = .current) -> LimitDisplay {
        let pace = Pace.assess(limit, now: now)
        let resetText = UsageFormatting.resetText(resetsAt: limit.resetsAt, now: now, calendar: calendar)
        let used = limit.percentUsed

        // §10 / P6: a Limit with a Window but no reset time has no active Window.
        if limit.windowLength != nil, limit.resetsAt == nil {
            return LimitDisplay(
                id: id, name: limit.name, percentText: UsageFormatting.percentText(used),
                fillFraction: 0, markerFraction: nil, band: .neutral, paceLabel: nil,
                detailText: "No active session", compactText: "No active session",
                isLimitReached: false, noActiveSession: true
            )
        }

        if let used, used >= Pace.limitReachedThreshold {
            return LimitDisplay(
                id: id, name: limit.name, percentText: UsageFormatting.percentText(used),
                fillFraction: 1, markerFraction: pace.markerPercent.map { $0 / 100 }, band: .red, paceLabel: nil,
                detailText: resetText.map { "Limit reached · \($0)" } ?? "Limit reached",
                compactText: "Limit reached",
                isLimitReached: true, noActiveSession: false
            )
        }

        return LimitDisplay(
            id: id, name: limit.name, percentText: UsageFormatting.percentText(used),
            fillFraction: min(max((used ?? 0) / 100, 0), 1),
            markerFraction: pace.markerPercent.map { $0 / 100 },
            band: pace.band, paceLabel: pace.label,
            detailText: used == nil ? "No usage figure" : resetText,
            compactText: used == nil ? "No usage figure" : nil,
            isLimitReached: false, noActiveSession: false
        )
    }
}
