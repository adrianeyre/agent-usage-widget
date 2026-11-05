import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageHostKit

/// A Provider whose answer each test sets per Account.
final class StubProvider: UsageProvider, @unchecked Sendable {
    var results: [UUID: Result<[LimitUsage], UsageProviderError>] = [:]
    var fetchCount = 0
    private let lock = NSLock()

    func fetch(for account: Account) async throws -> UsageSnapshot {
        let result = lock.withLock { () -> Result<[LimitUsage], UsageProviderError>? in
            fetchCount += 1
            return results[account.id]
        }
        switch result ?? .success([]) {
        case .success(let limits): return UsageSnapshot(accountID: account.id, limits: limits, fetchedAt: Date())
        case .failure(let error): throw error
        }
    }
}

final class MemoryAccountStore: AccountStore, @unchecked Sendable {
    var accounts: [Account] = []
    func load() -> [Account] { accounts }
    func save(_ accounts: [Account]) throws { self.accounts = accounts }
}

@MainActor
struct Harness {
    let model: AppModel
    let provider = StubProvider()
    let authorisations = InMemoryAuthorisationStore()
    let accountStore = MemoryAccountStore()
    let published: PublishedStore
    let root: URL
    let reloads: Counter

    final class Counter { var value = 0 }

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-usage-tests-\(UUID().uuidString)")
        published = PublishedStore(root: root)
        let reloads = Counter()
        self.reloads = reloads
        model = AppModel(
            accountStore: accountStore,
            authorisations: authorisations,
            publishedStore: published,
            providers: ProviderRegistry(providers: [.claude: provider, .copilot: provider]),
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            reloadWidgets: { reloads.value += 1 }
        )
    }

    func addClaude(_ name: String, _ email: String, org: String? = nil) throws -> Account {
        try model.add(Account(provider: .claude, name: name, email: email, emailVerified: true, organisationID: org), authorisation: nil)
    }

    func addCopilot(_ name: String, token: String = "github_pat_test") throws -> Account {
        try model.add(Account(provider: .copilot, name: name, email: "@\(name)", emailVerified: true), authorisation: token)
    }
}

private let session = LimitUsage(name: "Session (5h)", percentUsed: 45, windowLength: WindowLength.claudeSession, resetsAt: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 7200).rounded()))

@Suite("App model")
@MainActor
struct AppModelTests {
    @Test("Two Accounts each publish their own name and email (§12 #7)")
    func twoAccounts() async throws {
        let h = Harness()
        let work = try h.addClaude("Work", "work@example.com", org: "org-w")
        let personal = try h.addClaude("Personal", "me@example.com", org: "org-p")
        h.provider.results[work.id] = .success([session])
        h.provider.results[personal.id] = .success([session])
        await h.model.refreshAll()

        #expect(h.published.readIndex().accounts.map(\.name) == ["Work", "Personal"])
        #expect(h.published.readAccount(work.id)?.email == "work@example.com")
        #expect(h.published.readAccount(personal.id)?.email == "me@example.com")
        #expect(h.published.readAccount(work.id)?.snapshot?.limits == [session])
        #expect(h.reloads.value > 0)
    }

    @Test("A duplicate is refused and points to the existing Account (A5, §12 #8)")
    func duplicateRefused() throws {
        let h = Harness()
        let existing = try h.addClaude("Work", "you@example.com", org: "org-1")
        #expect(throws: AccountError.duplicate(existing: existing)) {
            try h.addClaude("Other", "you@example.com", org: "org-1")
        }
        let noOrg = try h.addClaude("x@example.com", "x@example.com")
        #expect(throws: AccountError.duplicate(existing: noOrg)) {
            try h.addClaude("x@example.com", "x@example.com")
        }
        #expect(h.model.accounts.count == 2)
        #expect(h.authorisations.count == 0, "Claude Accounts hold no Authorisation (ADR-0008)")
    }

    @Test("One Account failing never affects another (A7, §12 #6)")
    func failuresStaySeparate() async throws {
        let h = Harness()
        let good = try h.addClaude("Good", "good@example.com")
        let revoked = try h.addClaude("Revoked", "revoked@example.com")
        h.provider.results[good.id] = .success([session])
        h.provider.results[revoked.id] = .success([session])
        await h.model.refreshAll()

        h.provider.results[revoked.id] = .failure(.authorisationRejected)
        await h.model.refreshAll()

        let revokedFile = try #require(h.published.readAccount(revoked.id))
        #expect(revokedFile.signInRequired)
        if case .account(let card) = DisplayModel.content(for: revokedFile, now: Date()) {
            #expect(card.limits.isEmpty, "never 0% in place of Sign in required")
            #expect(card.status == .signInRequired)
        } else {
            Issue.record("expected an Account card")
        }
        #expect(h.published.readAccount(good.id)?.signInRequired == false)
        #expect(h.model.card(for: good).status == .ok)
    }

    @Test("A network failure keeps the last Snapshot (§10)")
    func offlineKeepsSnapshot() async throws {
        let h = Harness()
        let account = try h.addClaude("Work", "w@example.com")
        h.provider.results[account.id] = .success([session])
        await h.model.refreshAll()
        h.provider.results[account.id] = .failure(.network("offline"))
        await h.model.refreshAll()
        let file = try #require(h.published.readAccount(account.id))
        #expect(file.snapshot?.limits == [session])
        #expect(!file.signInRequired)
        #expect(h.model.runtime[account.id]?.lastError != nil)
    }

    @Test("Re-authorise fixes Sign in required and replaces the Authorisation (§12 #6, U2)")
    func reauthorise() async throws {
        let h = Harness()
        let account = try h.addCopilot("Work", token: "old")
        h.provider.results[account.id] = .failure(.authorisationRejected)
        await h.model.refreshAll()
        #expect(h.model.card(for: account).status == .signInRequired)

        h.provider.results[account.id] = .success([session])
        let created = Date().addingTimeInterval(-100)
        try await h.model.reauthorise(account.id, with: "new", createdAt: created)
        #expect(try h.authorisations.read(account.id) == "new")
        #expect(h.authorisations.count == 1)
        #expect(h.model.account(account.id)?.authorisationCreatedAt == created)
        #expect(h.model.card(for: h.model.account(account.id)!).status == .ok)
    }

    @Test("An Authorisation within 7 days of expiry shows Re-authorise by (§12 #9)")
    func expiryWarning() async throws {
        let h = Harness()
        var account = Account(provider: .copilot, name: "Old", email: "@old", emailVerified: true)
        account.enteredAuthorisationExpiry = Date().addingTimeInterval(5 * 86400)
        let added = try h.model.add(account, authorisation: "t")
        h.provider.results[added.id] = .success([session])
        await h.model.refreshAll()
        guard case .reauthoriseBy = h.model.card(for: added).status else {
            Issue.record("expected Re-authorise by, got \(h.model.card(for: added).status)")
            return
        }
        #expect(h.published.readAccount(added.id)?.authorisationExpiresAt != nil)
    }

    @Test("Removing an Account deletes its Keychain item and Snapshot (A6)")
    func remove() async throws {
        let h = Harness()
        let account = try h.addClaude("Work", "w@example.com")
        h.provider.results[account.id] = .success([session])
        await h.model.refreshAll()
        #expect(h.published.readAccount(account.id) != nil)

        try h.model.remove(account.id)
        #expect(try h.authorisations.read(account.id) == nil)
        #expect(h.published.readAccount(account.id) == nil)
        #expect(h.published.readIndex().accounts.isEmpty)
        #expect(h.accountStore.accounts.isEmpty)
        // A widget still pointing at it now shows Choose an Account (§6.1).
        #expect(DisplayModel.content(for: h.published.readAccount(account.id), now: Date()) == .chooseAccount)
    }

    @Test("Rename and re-order are saved and published in order (A2, A4)")
    func renameAndMove() throws {
        let h = Harness()
        let a = try h.addClaude("A", "a@example.com")
        let b = try h.addClaude("B", "b@example.com")
        try h.model.rename(a.id, to: "Alpha")
        #expect(throws: AccountError.nameTaken("b")) { try h.model.rename(a.id, to: "b") }
        try h.model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(h.model.accounts.map(\.id) == [b.id, a.id])
        #expect(h.published.readIndex().accounts.map(\.name) == ["B", "Alpha"])
        #expect(h.accountStore.accounts.map(\.name) == ["B", "Alpha"])
    }

    @Test("Move Up and Move Down change the order one place at a time, saved and published (A4)")
    func moveUpAndDown() throws {
        let h = Harness()
        let a = try h.addClaude("A", "a@example.com")
        let b = try h.addClaude("B", "b@example.com")
        let c = try h.addClaude("C", "c@example.com")

        #expect(!h.model.canMove(a.id, .up))
        #expect(!h.model.canMove(c.id, .down))
        #expect(h.model.canMove(b.id, .up) && h.model.canMove(b.id, .down))

        try h.model.move(c.id, .up)
        #expect(h.model.accounts.map(\.name) == ["A", "C", "B"])
        try h.model.move(a.id, .down)
        #expect(h.model.accounts.map(\.name) == ["C", "A", "B"])
        #expect(h.accountStore.accounts.map(\.name) == ["C", "A", "B"])
        #expect(h.published.readIndex().accounts.map(\.name) == ["C", "A", "B"])

        // At either end, nothing changes.
        try h.model.move(c.id, .up)
        try h.model.move(b.id, .down)
        #expect(h.model.accounts.map(\.name) == ["C", "A", "B"])
        #expect(throws: AccountError.notFound) { try h.model.move(UUID(), .up) }
    }

    @Test("Accounts and Snapshots survive a restart")
    func restore() async throws {
        let h = Harness()
        let account = try h.addClaude("Work", "w@example.com")
        h.provider.results[account.id] = .success([session])
        await h.model.refreshAll()

        let restarted = AppModel(
            accountStore: h.accountStore, authorisations: h.authorisations, publishedStore: h.published,
            providers: ProviderRegistry(providers: [:]), reloadWidgets: {}
        )
        #expect(restarted.accounts.map(\.id) == [account.id])
        #expect(restarted.runtime[account.id]?.snapshot?.limits == [session])
    }

    @Test("A Provider with no data source in this build fails on its own")
    func unsupportedProvider() async throws {
        let h = Harness()
        let fixture = try h.model.add(Account(provider: .fixture, name: "F", email: "f@example.com", emailVerified: true), authorisation: nil)
        await h.model.refreshAll()
        #expect(h.model.runtime[fixture.id]?.lastError != nil)
        #expect(h.model.runtime[fixture.id]?.signInRequired == false)
    }
}
