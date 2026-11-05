import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageHostKit

/// Stands in for `codex app-server`, answering each method with canned JSON.
struct StubCodexServer: CodexAppServer {
    var answers: [String: String]
    var error: UsageProviderError?

    func call(home: URL, method: String, params: [String: Any]?) async throws -> [String: Any] {
        if let error { throw error }
        let json = answers[method] ?? "{}"
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }
}

@Suite("Codex Provider")
struct CodexProviderTests {
    let account = Account(provider: .codex, name: "Personal", email: "me@example.com", emailVerified: true)

    func provider(_ server: StubCodexServer) throws -> (CodexUsageProvider, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-tests-\(UUID().uuidString)")
        let homes = CodexHomes(root: root)
        _ = try homes.prepare(account.id)
        return (CodexUsageProvider(server: server, homes: homes), root)
    }

    // The shape of `account/rateLimits/read` in codex-cli 0.166.0 (#26).
    static let plus = """
    {"rateLimits":{"limitId":"codex","planType":"plus",
      "primary":{"usedPercent":45,"windowDurationMins":300,"resetsAt":1793872800},
      "secondary":{"usedPercent":71,"windowDurationMins":10080,"resetsAt":1794218400}},
     "rateLimitsByLimitId":null}
    """

    @Test("Reads 5h and Weekly from usedPercent, windowDurationMins and resetsAt")
    func plusPlan() async throws {
        let (provider, root) = try provider(StubCodexServer(answers: ["account/rateLimits/read": Self.plus]))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try await provider.fetch(for: account)
        #expect(snapshot.limits.map(\.name) == ["5h", "Weekly"])
        #expect(snapshot.limits[0].percentUsed == 45)
        #expect(snapshot.limits[0].windowLength == TimeInterval(5 * 60 * 60))
        #expect(snapshot.limits[0].resetsAt == Date(timeIntervalSince1970: 1793872800))
        #expect(snapshot.limits[1].windowLength == TimeInterval(7 * 24 * 60 * 60))
        #expect(snapshot.authorisationExpiresAt == nil, "a ChatGPT login has no known expiry (U3)")
    }

    @Test("ChatGPT Pro shows Weekly only, and the codex bucket is preferred")
    func proPlan() async throws {
        let body = """
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1794218400},"secondary":null}}}
        """
        let (provider, root) = try provider(StubCodexServer(answers: ["account/rateLimits/read": body]))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try await provider.fetch(for: account)
        #expect(snapshot.limits.map(\.name) == ["Weekly"])
        #expect(snapshot.limits[0].percentUsed == 12)
    }

    @Test("A window without a length has no Pace marker (P0); no windows is an error (R6)")
    func missingFields() async throws {
        let body = #"{"rateLimits":{"primary":{"usedPercent":30}}}"#
        let (provider, root) = try provider(StubCodexServer(answers: ["account/rateLimits/read": body]))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try await provider.fetch(for: account)
        #expect(snapshot.limits[0].windowLength == nil)
        #expect(snapshot.limits[0].resetsAt == nil)

        let (empty, root2) = try self.provider(StubCodexServer(answers: ["account/rateLimits/read": #"{"rateLimits":{}}"#]))
        defer { try? FileManager.default.removeItem(at: root2) }
        await #expect(throws: UsageProviderError.self) { try await empty.fetch(for: account) }
    }

    @Test("No Codex home means no Authorisation")
    func noHome() async throws {
        let homes = CodexHomes(root: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)"))
        let provider = CodexUsageProvider(server: StubCodexServer(answers: [:]), homes: homes)
        await #expect(throws: UsageProviderError.authorisationMissing) { try await provider.fetch(for: account) }
    }

    @Test("app-server's authentication error means Sign in required (R5)")
    func authenticationError() throws {
        let message: [String: Any] = ["id": 2, "error": ["code": -32600, "message": "codex account authentication required to read rate limits"]]
        #expect(throws: UsageProviderError.authorisationRejected) { try CodexProcessServer.result(of: message) }
        let other: [String: Any] = ["id": 2, "error": ["code": -32601, "message": "method not found"]]
        #expect(throws: UsageProviderError.unexpectedResponse("codex: method not found")) { try CodexProcessServer.result(of: other) }
    }

    @Test("account/read gives the email and plan (A3, A5); signed out is Sign in required")
    func profile() throws {
        let signedIn: [String: Any] = ["account": ["type": "chatgpt", "email": "me@example.com", "planType": "plus"], "requiresOpenaiAuth": true]
        let profile = try CodexUsageProvider.parseProfile(signedIn)
        #expect(profile.email == "me@example.com")
        #expect(profile.planType == "plus")
        let signedOut: [String: Any] = ["account": NSNull(), "requiresOpenaiAuth": true]
        #expect(throws: UsageProviderError.authorisationRejected) { try CodexUsageProvider.parseProfile(signedOut) }
    }

    @Test("Each home keeps Codex's login in the Keychain and is the Account's own folder")
    func homes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-homes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let homes = CodexHomes(root: root)
        let home = try homes.prepare(account.id)
        #expect(home.lastPathComponent == account.id.uuidString)
        let config = try String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(config.contains(#"cli_auth_credentials_store = "keyring""#))
        #expect(CodexCLI.environment(home: home)["CODEX_HOME"] == home.path)
        #expect(!home.path.hasSuffix("/.codex"))
    }

    @Test("The real codex app-server, in an empty home, says Sign in required", .enabled(if: CodexCLI.executable() != nil))
    func realServerSignedOut() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-real-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let homes = CodexHomes(root: root)
        _ = try homes.prepare(account.id)
        let provider = CodexUsageProvider(server: CodexProcessServer(), homes: homes)
        await #expect(throws: UsageProviderError.authorisationRejected) { try await provider.fetch(for: account) }
        let profile = try await CodexProcessServer().call(home: homes.home(for: account.id), method: "account/read", params: ["refreshToken": false])
        #expect(profile["account"] is NSNull)
    }

    /// Run by hand against a signed-in dedicated home (#26):
    /// `CODEX_PROBE_HOME=<folder> swift test --filter realServerSignedIn`
    @Test("A signed-in dedicated home gives real 5h and Weekly figures",
          .enabled(if: ProcessInfo.processInfo.environment["CODEX_PROBE_HOME"] != nil && CodexCLI.executable() != nil))
    func realServerSignedIn() async throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_PROBE_HOME"]!, isDirectory: true)
        let id = UUID(uuidString: home.lastPathComponent) ?? account.id
        let homes = CodexHomes(root: home.deletingLastPathComponent())
        var probe = account
        probe.id = id
        let snapshot: UsageSnapshot
        if UUID(uuidString: home.lastPathComponent) == nil {
            // Not named after an Account: call the server directly.
            let result = try await CodexProcessServer().call(home: home, method: "account/rateLimits/read", params: nil)
            snapshot = try CodexUsageProvider.parseRateLimits(result, accountID: id, fetchedAt: Date())
        } else {
            snapshot = try await CodexUsageProvider(homes: homes).fetch(for: probe)
        }
        print("codex probe:", snapshot.limits.map { "\($0.name) \($0.percentUsed ?? -1)% resets \($0.resetsAt.map(String.init(describing:)) ?? "-")" })
        #expect(snapshot.limits.map(\.name).last == "Weekly")
        #expect(snapshot.limits.allSatisfy { $0.percentUsed != nil && $0.resetsAt != nil })
        let profile = try await CodexUsageProvider.fetchProfile(home: home)
        #expect(profile.email != nil)
    }

    @Test("Limit names come from the Window length (PV2)")
    func names() {
        #expect(WindowLength.name(forWindow: 5 * 3600) == "5h")
        #expect(WindowLength.name(forWindow: 7 * 86400) == "Weekly")
        #expect(WindowLength.name(forWindow: 86400) == "Daily")
        #expect(WindowLength.name(forWindow: 3 * 86400) == "3d")
    }
}

struct HeaderHTTP: HTTPClient {
    let status: Int
    let body: String
    var headers: [String: String] = [:]
    var check: @Sendable (URLRequest) -> Void = { _ in }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        check(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

@Suite("Copilot Provider")
struct CopilotProviderTests {
    let account = Account(provider: .copilot, name: "GitHub", email: "@octo", emailVerified: true)

    func provider(_ http: any HTTPClient) throws -> CopilotUsageProvider {
        let store = InMemoryAuthorisationStore()
        try store.save("github_pat_secret", for: account.id)
        return CopilotUsageProvider(authorisations: store, http: http)
    }

    // A paid plan billed in credits.
    static let paid = """
    {"login":"octo","copilot_plan":"individual","token_based_billing":true,
     "quota_snapshots":{
       "premium_interactions":{"entitlement":1500,"remaining":900,"percent_remaining":60.0,"unlimited":false,"credits_used":600},
       "chat":{"entitlement":0,"unlimited":true},
       "completions":{"entitlement":0,"unlimited":true}},
     "quota_reset_date":"2026-12-01","quota_reset_date_utc":"2026-12-01T00:00:00.000Z"}
    """

    // Copilot Free, as returned on 5 November 2026 (#27).
    static let free = """
    {"login":"octo","access_type_sku":"free_limited_copilot","copilot_plan":"individual",
     "quota_snapshots":{
       "chat":{"overage_count":0,"percent_remaining":100.0,"quota_id":"chat","quota_remaining":200.0,"unlimited":false,"has_quota":true,"token_based_billing":true,"credits_used":0,"remaining":200,"entitlement":200},
       "completions":{"percent_remaining":99.1,"quota_id":"completions","quota_remaining":1983.0,"unlimited":false,"credits_used":17,"remaining":1983,"entitlement":2000},
       "premium_interactions":{"percent_remaining":0.0,"quota_remaining":0.0,"unlimited":false,"has_quota":false,"credits_used":0,"remaining":0,"entitlement":0}},
     "token_based_billing":true,"quota_reset_date":"2026-12-01","quota_reset_date_utc":"2026-12-01T00:00:00.000Z"}
    """

    @Test("Monthly credits as a percentage, over the UTC calendar month (PV2)")
    func paidPlan() async throws {
        let http = HeaderHTTP(status: 200, body: Self.paid, headers: ["github-authentication-token-expiration": "2027-11-05 10:00:00 UTC"]) { request in
            #expect(request.url == CopilotUsageProvider.usageURL)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer github_pat_secret")
        }
        let snapshot = try await provider(http).fetch(for: account)
        #expect(snapshot.limits.map(\.name) == ["Monthly credits"])
        #expect(snapshot.limits[0].percentUsed == 40)
        let reset = ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z")!
        #expect(snapshot.limits[0].resetsAt == reset)
        #expect(snapshot.limits[0].windowLength == TimeInterval(30 * 86400), "November has 30 days")
        #expect(snapshot.authorisationExpiresAt == ISO8601DateFormatter().date(from: "2027-11-05T10:00:00Z"))
    }

    @Test("Copilot Free shows its Chat and Completions allowances")
    func freePlan() async throws {
        let snapshot = try await provider(HeaderHTTP(status: 200, body: Self.free)).fetch(for: account)
        #expect(snapshot.limits.map(\.name) == ["Chat", "Completions"])
        #expect(snapshot.limits[0].percentUsed == 0)
        #expect(abs(snapshot.limits[1].percentUsed! - 0.85) < 0.001)
        #expect(snapshot.authorisationExpiresAt == nil)
    }

    @Test("A refused token is Sign in required (R5); no quotas is an error, not zeros (R6)")
    func failures() async throws {
        for status in [401, 403, 404] {
            await #expect(throws: UsageProviderError.authorisationRejected) {
                try await provider(HeaderHTTP(status: status, body: #"{"message":"Bad credentials"}"#)).fetch(for: account)
            }
        }
        await #expect(throws: UsageProviderError.self) {
            try await provider(HeaderHTTP(status: 200, body: #"{"login":"octo"}"#)).fetch(for: account)
        }
    }

    @Test("The username, plus the primary email when readable (PV6)")
    func profile() async throws {
        let user = try CopilotUsageProvider.parseUser(Data(#"{"login":"octo","id":42,"email":null}"#.utf8))
        #expect(user.accountEmail == "@octo")
        #expect(user.userID == "42")
        let email = CopilotUsageProvider.parsePrimaryEmail(Data(#"[{"email":"a@x.com","primary":false},{"email":"o@x.com","primary":true}]"#.utf8))
        #expect(email == "o@x.com")
        var withEmail = user
        withEmail.email = email
        #expect(withEmail.accountEmail == "@octo · o@x.com")
    }

    @MainActor
    func model(_ http: any HTTPClient, store: InMemoryAuthorisationStore, root: URL) -> AppModel {
        AppModel(
            accountStore: FileAccountStore(url: root.appendingPathComponent("accounts.json")),
            authorisations: store,
            publishedStore: PublishedStore(root: root.appendingPathComponent("widget")),
            providers: ProviderRegistry(providers: [.copilot: CopilotUsageProvider(authorisations: store, http: http)]),
            defaults: UserDefaults(suiteName: "copilot-\(UUID().uuidString)")!,
            reloadWidgets: {}
        )
    }

    @Test("Without GitHub's header, the expiry the Owner entered gives Re-authorise by (U3)")
    @MainActor
    func enteredExpiry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryAuthorisationStore()
        let model = model(HeaderHTTP(status: 200, body: Self.paid), store: store, root: root)
        let entered = Date().addingTimeInterval(5 * 86400)
        var candidate = account
        candidate.enteredAuthorisationExpiry = entered
        let added = try model.add(candidate, authorisation: "github_pat_secret")
        await model.refresh(added.id)
        #expect(StatusRules.status(of: model.published(added), now: Date()) == .reauthoriseBy(entered))

        // A new token with no expiry clears the warning (a "No expiration" token).
        try await model.reauthorise(added.id, with: "github_pat_new", enteredExpiry: nil)
        let refreshed = try #require(model.account(added.id))
        #expect(refreshed.enteredAuthorisationExpiry == nil)
        #expect(StatusRules.status(of: model.published(refreshed), now: Date()) == .ok)
    }

    @Test("GitHub's header wins over an entered expiry (U3)")
    @MainActor
    func headerWins() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let http = HeaderHTTP(status: 200, body: Self.paid, headers: ["github-authentication-token-expiration": "2027-11-05 10:00:00 UTC"])
        let model = model(http, store: InMemoryAuthorisationStore(), root: root)
        var candidate = account
        candidate.enteredAuthorisationExpiry = Date().addingTimeInterval(2 * 86400)
        let added = try model.add(candidate, authorisation: "github_pat_secret")
        await model.refresh(added.id)
        #expect(model.published(added).authorisationExpiresAt == ISO8601DateFormatter().date(from: "2027-11-05T10:00:00Z"))
    }

    @Test("The token's expiry flows into Re-authorise by (U3)")
    @MainActor
    func expiryReachesStatus() async throws {
        let store = InMemoryAuthorisationStore()
        let expires = Date().addingTimeInterval(3 * 86400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        let http = HeaderHTTP(status: 200, body: Self.paid, headers: ["github-authentication-token-expiration": formatter.string(from: expires)])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            accountStore: FileAccountStore(url: root.appendingPathComponent("accounts.json")),
            authorisations: store,
            publishedStore: PublishedStore(root: root.appendingPathComponent("widget")),
            providers: ProviderRegistry(providers: [.copilot: CopilotUsageProvider(authorisations: store, http: http)]),
            defaults: UserDefaults(suiteName: "copilot-\(UUID().uuidString)")!,
            reloadWidgets: {}
        )
        let added = try model.add(account, authorisation: "github_pat_secret")
        await model.refresh(added.id)
        guard case .reauthoriseBy(let date) = StatusRules.status(of: model.published(added), now: Date()) else {
            Issue.record("expected Re-authorise by")
            return
        }
        #expect(abs(date.timeIntervalSince(expires)) < 1)
    }
}
