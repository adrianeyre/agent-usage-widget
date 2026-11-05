import Foundation

/// One Limit as a Provider reports it (PRD §7.3). Every field a Provider might not
/// send is optional, so a missing field becomes `nil` rather than a crash.
public struct LimitUsage: Codable, Hashable, Sendable {
    /// e.g. "Session (5h)", "Weekly".
    public var name: String
    /// 0–100. Can exceed 100 when a Provider reports overage.
    public var percentUsed: Double?
    /// The Window length. `nil` means no Pace marker or pace colouring (P0).
    public var windowLength: TimeInterval?
    public var resetsAt: Date?

    public init(name: String, percentUsed: Double?, windowLength: TimeInterval?, resetsAt: Date?) {
        self.name = name
        self.percentUsed = percentUsed
        self.windowLength = windowLength
        self.resetsAt = resetsAt
    }
}

/// The most recent usage figures fetched for an Account, together with when they were fetched.
public struct UsageSnapshot: Codable, Hashable, Sendable {
    public var accountID: UUID
    /// In the Provider's display order. The widget shows up to two.
    public var limits: [LimitUsage]
    public var fetchedAt: Date
    /// When the Provider says the Authorisation expires, if it says so with each fetch
    /// (Copilot's `github-authentication-token-expiration` header, U3). Never the secret itself.
    public var authorisationExpiresAt: Date?

    public init(accountID: UUID, limits: [LimitUsage], fetchedAt: Date, authorisationExpiresAt: Date? = nil) {
        self.accountID = accountID
        self.limits = limits
        self.fetchedAt = fetchedAt
        self.authorisationExpiresAt = authorisationExpiresAt
    }
}

/// The Providers the app knows about. `fixture` is the debug-only canned data source:
/// the enum case exists in every build so files stay decodable, but only Debug builds
/// can create a fixture Account.
public enum ProviderKind: String, Codable, Hashable, Sendable, CaseIterable {
    case claude
    case codex
    case copilot
    case fixture

    /// Shown as text, with a neutral glyph and no logos (PV4).
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .fixture: "Fixture"
        }
    }

    /// SF Symbol name for the neutral Provider glyph.
    public var glyphSystemName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "terminal"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .fixture: "testtube.2"
        }
    }
}

/// Window lengths for the Limits the app knows about.
public enum WindowLength {
    public static let claudeSession: TimeInterval = 5 * 60 * 60
    public static let claudeWeekly: TimeInterval = 7 * 24 * 60 * 60

    /// A Limit's name from its Window length, as Codex reports it (PV2): `5h`, `Weekly`,
    /// `Daily`, otherwise whole hours or days, e.g. `12h`, `3d`.
    public static func name(forWindow length: TimeInterval) -> String {
        let minutes = Int((length / 60).rounded())
        switch minutes {
        case 7 * 24 * 60: return "Weekly"
        case 24 * 60: return "Daily"
        case let m where m % (24 * 60) == 0: return "\(m / (24 * 60))d"
        case let m where m % 60 == 0: return "\(m / 60)h"
        default: return "\(minutes)m"
        }
    }

    /// The UTC calendar month that ends at `reset` (Copilot's Monthly credits Window, PV2).
    public static func utcMonth(endingAt reset: Date) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return 30 * 24 * 60 * 60 }
        return reset.timeIntervalSince(start)
    }
}
