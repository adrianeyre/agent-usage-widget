import AgentUsageCore
import Foundation

/// Canned behaviour for a debug-only fixture Account. The values exist in every build so
/// files stay decodable, but only Debug builds have the fixture data source.
public enum FixtureScenario: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal = "Session 45%, Weekly 71%"
    case overPace = "Over pace"
    case limitReached = "Limit reached"
    case noActiveSession = "No active session"
    case signInRequired = "Sign in required"
    case offline = "Offline (fetch fails)"

    public var id: String { rawValue }
}

/// One set of usage limits at one Provider (A1). Host-only: the widget sees a
/// `PublishedAccount`, and the Authorisation lives in its own private file, never here.
public struct Account: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var provider: ProviderKind
    /// Required and unique (A2).
    public var name: String
    public var email: String
    /// False when the Owner typed the email in (A3).
    public var emailVerified: Bool
    public var organisationID: String?
    public var organisationName: String?
    /// When the current Authorisation was created; Claude's expires a year later (U3).
    public var authorisationCreatedAt: Date?
    /// The expiry the Owner typed in when the Provider doesn't report one (Copilot, U3).
    /// `nil` means unknown or none.
    public var enteredAuthorisationExpiry: Date?
    public var fixtureScenario: FixtureScenario?

    public init(
        id: UUID = UUID(),
        provider: ProviderKind,
        name: String,
        email: String,
        emailVerified: Bool,
        organisationID: String? = nil,
        organisationName: String? = nil,
        authorisationCreatedAt: Date? = nil,
        enteredAuthorisationExpiry: Date? = nil,
        fixtureScenario: FixtureScenario? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.organisationID = organisationID
        self.organisationName = organisationName
        self.authorisationCreatedAt = authorisationCreatedAt
        self.enteredAuthorisationExpiry = enteredAuthorisationExpiry
        self.fixtureScenario = fixtureScenario
    }

    /// The expiry the Owner entered, if any. Claude Accounts hold no Authorisation (ADR-0008),
    /// and Copilot's reported expiry comes with each fetch instead (U3).
    public var authorisationExpiresAt: Date? {
        enteredAuthorisationExpiry
    }
}

public enum AccountError: LocalizedError, Equatable {
    case nameRequired
    case nameTaken(String)
    case emailRequired
    case duplicate(existing: Account)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "An Account name is required."
        case .nameTaken(let name): "Another Account is already called “\(name)”."
        case .emailRequired: "An Account email is required."
        case .duplicate(let existing): "This Account has already been added as “\(existing.name)”."
        case .notFound: "That Account no longer exists."
        }
    }
}

/// The rules for adding and renaming Accounts (A2, A5).
public enum AccountRules {
    static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The trimmed name, or an error if it's empty or used by another Account (A2).
    public static func validatedName(_ name: String, for id: UUID?, among accounts: [Account]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.nameRequired }
        if accounts.contains(where: { $0.id != id && normalised($0.name) == normalised(trimmed) }) {
            throw AccountError.nameTaken(trimmed)
        }
        return trimmed
    }

    /// The existing Account that `candidate` duplicates, if any (A5).
    ///
    /// Same Provider and email, plus the same organisation when both organisations are
    /// known, or the same Account name when either can't be read.
    public static func duplicate(of candidate: Account, among accounts: [Account]) -> Account? {
        accounts.first { existing in
            guard existing.id != candidate.id,
                  existing.provider == candidate.provider,
                  normalised(existing.email) == normalised(candidate.email)
            else { return false }
            if let a = existing.organisationID, let b = candidate.organisationID {
                return a == b
            }
            return normalised(existing.name) == normalised(candidate.name)
        }
    }
}
