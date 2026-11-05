import Foundation

/// What the host app publishes for one Account so the widget can draw it (ADR-0002, ADR-0004).
/// It holds the Account name and email for the header, the latest Snapshot and the
/// Authorisation state, but never the Authorisation itself (§7.3).
public struct PublishedAccount: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var provider: ProviderKind
    public var name: String
    public var email: String
    /// False when the Owner typed the email in because it couldn't be read (A3).
    public var emailVerified: Bool
    /// When the Authorisation is expected to expire, if that's known (U3).
    public var authorisationExpiresAt: Date?
    /// The last fetch was refused because the Authorisation failed or was revoked (R5).
    public var signInRequired: Bool
    /// The last successful fetch, kept when later fetches fail (§10, network offline).
    public var snapshot: UsageSnapshot?

    public init(
        id: UUID,
        provider: ProviderKind,
        name: String,
        email: String,
        emailVerified: Bool = true,
        authorisationExpiresAt: Date? = nil,
        signInRequired: Bool = false,
        snapshot: UsageSnapshot? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.authorisationExpiresAt = authorisationExpiresAt
        self.signInRequired = signInRequired
        self.snapshot = snapshot
    }
}

/// One entry in the widget's Account picker, in the Manage Accounts order (§6.1).
public struct PublishedAccountSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var provider: ProviderKind
    public var name: String
    public var email: String

    public init(id: UUID, provider: ProviderKind, name: String, email: String) {
        self.id = id
        self.provider = provider
        self.name = name
        self.email = email
    }

    public init(_ account: PublishedAccount) {
        self.init(id: account.id, provider: account.provider, name: account.name, email: account.email)
    }
}

public struct PublishedIndex: Codable, Hashable, Sendable {
    public var accounts: [PublishedAccountSummary]

    public init(accounts: [PublishedAccountSummary]) {
        self.accounts = accounts
    }
}
