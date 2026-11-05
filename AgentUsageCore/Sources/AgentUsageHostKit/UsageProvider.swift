import AgentUsageCore
import Foundation

/// Every Provider's fetching code sits behind this (PRD §7.3).
public protocol UsageProvider: Sendable {
    func fetch(for account: Account) async throws -> UsageSnapshot
    /// Deletes anything the Provider keeps for the Account outside its Authorisation file,
    /// e.g. a Codex home (A6). Never touches the Provider's own CLI or app login.
    func forget(_ account: Account) async
}

extension UsageProvider {
    public func forget(_ account: Account) async {}
}

public enum UsageProviderError: LocalizedError, Equatable {
    /// No Authorisation is stored for the Account.
    case authorisationMissing
    /// The Provider refused the Authorisation: it failed, expired or was revoked (R5).
    case authorisationRejected
    /// The Provider answered with something the app couldn't read.
    case unexpectedResponse(String)
    /// The fetch didn't reach the Provider. The last Snapshot is kept (§10).
    case network(String)
    /// This build has no data source for the Provider.
    case unsupportedProvider
    /// Nothing has been reported yet, e.g. Claude Code hasn't answered since the feed was installed.
    case noDataYet

    public var errorDescription: String? {
        switch self {
        case .authorisationMissing: "No Authorisation is stored for this Account."
        case .authorisationRejected: "The Provider refused this Account's Authorisation."
        case .unexpectedResponse(let detail): "Unexpected response: \(detail)"
        case .network(let detail): "Couldn't reach the Provider: \(detail)"
        case .unsupportedProvider: "This build can't fetch usage for this Provider."
        case .noDataYet: "No usage reported yet. Figures arrive the next time Claude Code answers with this configuration."
        }
    }

    /// Whether the failure means `Sign in required` rather than a temporary problem.
    public var requiresSignIn: Bool {
        self == .authorisationMissing || self == .authorisationRejected
    }
}

/// Picks the data source for each Provider.
public struct ProviderRegistry: Sendable {
    private let providers: [ProviderKind: any UsageProvider]

    public init(providers: [ProviderKind: any UsageProvider]) {
        self.providers = providers
    }

    /// The real sources, plus the fixture source in Debug builds only.
    public static func live(authorisations: any AuthorisationStore, http: any HTTPClient = URLSession.shared) -> ProviderRegistry {
        var providers: [ProviderKind: any UsageProvider] = [
            .claude: ClaudeUsageProvider(),
            .codex: CodexUsageProvider(),
            .copilot: CopilotUsageProvider(authorisations: authorisations, http: http),
        ]
        #if DEBUG
        providers[.fixture] = FixtureUsageProvider()
        #endif
        return ProviderRegistry(providers: providers)
    }

    public func provider(for kind: ProviderKind) -> (any UsageProvider)? {
        providers[kind]
    }

    /// The Providers that can be chosen under Add Account in this build.
    public var addableProviders: [ProviderKind] {
        ProviderKind.allCases.filter { providers[$0] != nil }
    }
}

/// Lets tests stand in for the network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.unexpectedResponse("not an HTTP response")
        }
        return (data, http)
    }
}
