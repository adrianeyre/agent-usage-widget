import AgentUsageCore
import Foundation
import Observation
import WidgetKit

/// What the host app knows about an Account between fetches.
public struct AccountRuntime: Equatable, Sendable {
    /// The last successful fetch. Kept when later fetches fail (§10).
    public var snapshot: UsageSnapshot?
    public var signInRequired = false
    public var lastError: String?
    public var isFetching = false

    public init(snapshot: UsageSnapshot? = nil, signInRequired: Bool = false) {
        self.snapshot = snapshot
        self.signInRequired = signInRequired
    }
}

/// The host app's state: the ordered Accounts, their latest Snapshots and the refresh loop
/// (ADR-0002). Each Account is fetched and fails on its own (A7).
@MainActor
@Observable
public final class AppModel {
    public private(set) var accounts: [Account]
    public private(set) var runtime: [UUID: AccountRuntime] = [:]
    public private(set) var lastRefresh: Date?

    public let providers: ProviderRegistry
    let accountStore: any AccountStore
    let authorisations: any AuthorisationStore
    let publishedStore: PublishedStore
    let reloadWidgets: @MainActor () -> Void
    let defaults: UserDefaults
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(
        accountStore: any AccountStore,
        authorisations: any AuthorisationStore,
        publishedStore: PublishedStore,
        providers: ProviderRegistry,
        defaults: UserDefaults = .standard,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.accountStore = accountStore
        self.authorisations = authorisations
        self.publishedStore = publishedStore
        self.providers = providers
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets

        var accounts = accountStore.load()
        #if !DEBUG
        // A Release build has no fixture source, so fixture Accounts from a Debug build are dropped.
        accounts.removeAll { $0.provider == .fixture }
        #endif
        self.accounts = accounts
        // Restore the last Snapshots so Stale works across restarts (§10).
        for account in accounts {
            let published = publishedStore.readAccount(account.id)
            runtime[account.id] = AccountRuntime(snapshot: published?.snapshot, signInRequired: published?.signInRequired ?? false)
        }
    }

    /// The live app, storing everything in Application Support (Authorisations in `host/authorisations/`).
    public static func live() -> AppModel {
        // Claude no longer uses a status line wrapper (ADR-0011): put the Owner's back.
        LegacyClaudeStatusLine.restore()
        let authorisations = FileAuthorisationStore()
        return AppModel(
            accountStore: FileAccountStore(),
            authorisations: authorisations,
            publishedStore: PublishedStore(),
            providers: .live(authorisations: authorisations)
        )
    }

    // MARK: Display

    public func published(_ account: Account) -> PublishedAccount {
        let state = runtime[account.id] ?? AccountRuntime()
        return PublishedAccount(
            id: account.id,
            provider: account.provider,
            name: account.name,
            email: account.email,
            emailVerified: account.emailVerified,
            // What the Provider reports with each fetch wins over what was entered (U3).
            authorisationExpiresAt: state.snapshot?.authorisationExpiresAt ?? account.authorisationExpiresAt,
            signInRequired: state.signInRequired,
            snapshot: state.snapshot
        )
    }

    public func card(for account: Account, now: Date = Date()) -> AccountCard {
        DisplayModel.card(for: published(account), now: now)
    }

    public func account(_ id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: Refreshing (R1)

    /// Fetches every Account now, then every `RefreshInterval` seconds.
    public func startRefreshing() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                let interval = self.map { RefreshSettings.interval($0.defaults) } ?? RefreshSettings.defaultInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopRefreshing() {
        timer?.cancel()
        timer = nil
    }

    /// **Refresh now**: fetches every Account at once and restarts the interval.
    public func refreshNow() {
        startRefreshing()
    }

    /// Fetches every Account concurrently. One failing never affects another (A7).
    public func refreshAll() async {
        let targets = accounts
        for account in targets { runtime[account.id, default: AccountRuntime()].isFetching = true }

        let results = await withTaskGroup(of: (UUID, Result<UsageSnapshot, UsageProviderError>).self) { group in
            for account in targets {
                let provider = providers.provider(for: account.provider)
                group.addTask {
                    (account.id, await Self.fetch(account, with: provider))
                }
            }
            var results: [(UUID, Result<UsageSnapshot, UsageProviderError>)] = []
            for await result in group { results.append(result) }
            return results
        }
        for (id, result) in results { apply(result, to: id) }
        lastRefresh = Date()
        publish()
    }

    /// Fetches one Account, e.g. straight after it's added or re-authorised.
    public func refresh(_ id: UUID) async {
        guard let account = account(id) else { return }
        runtime[id, default: AccountRuntime()].isFetching = true
        let result = await Self.fetch(account, with: providers.provider(for: account.provider))
        apply(result, to: id)
        publish()
    }

    nonisolated static func fetch(_ account: Account, with provider: (any UsageProvider)?) async -> Result<UsageSnapshot, UsageProviderError> {
        guard let provider else { return .failure(.unsupportedProvider) }
        do {
            return .success(try await provider.fetch(for: account))
        } catch let error as UsageProviderError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    func apply(_ result: Result<UsageSnapshot, UsageProviderError>, to id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        var state = runtime[id] ?? AccountRuntime()
        state.isFetching = false
        switch result {
        case .success(let snapshot):
            state.snapshot = snapshot
            state.signInRequired = false
            state.lastError = nil
        case .failure(let error):
            // Keep the last Snapshot so markers keep moving and Stale appears after 30 min.
            if error.requiresSignIn { state.signInRequired = true }
            state.lastError = error.localizedDescription
        }
        runtime[id] = state
    }

    /// Writes every Account's published file and reloads the widgets (R1).
    func publish() {
        do {
            try publishedStore.publish(accounts.map(published))
        } catch {
            NSLog("Agent Usage: couldn't write Snapshots: %@", error.localizedDescription)
        }
        reloadWidgets()
    }

    // MARK: Managing Accounts (A2–A6)

    /// Adds an Account, storing its Authorisation first. Refuses duplicates (A5).
    @discardableResult
    public func add(_ candidate: Account, authorisation: String?) throws -> Account {
        var account = candidate
        account.email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.email.isEmpty else { throw AccountError.emailRequired }
        // A duplicate is reported first so the Owner is pointed to the existing Account (A5).
        if let existing = AccountRules.duplicate(of: account, among: accounts) {
            throw AccountError.duplicate(existing: existing)
        }
        account.name = try AccountRules.validatedName(account.name, for: account.id, among: accounts)
        if let authorisation {
            try authorisations.save(authorisation, for: account.id)
            account.authorisationCreatedAt = account.authorisationCreatedAt ?? Date()
        }
        accounts.append(account)
        runtime[account.id] = AccountRuntime()
        try persist()
        publish()
        return account
    }

    public func rename(_ id: UUID, to name: String) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
        accounts[index].name = try AccountRules.validatedName(name, for: id, among: accounts)
        try persist()
        publish()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        accounts.move(fromOffsets: source, toOffset: destination)
        try persist()
        publish()
    }

    public enum MoveDirection: Sendable { case up, down }

    /// Whether the Account can move one place that way: the first can't go up, the last can't go down.
    public func canMove(_ id: UUID, _ direction: MoveDirection) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }
        return direction == .up ? index > 0 : index < accounts.count - 1
    }

    /// Moves the Account one place up or down the order shown in the menu and the widget picker (A4).
    public func move(_ id: UUID, _ direction: MoveDirection) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
        guard canMove(id, direction) else { return }
        let target = direction == .up ? index - 1 : index + 1
        accounts.swapAt(index, target)
        try persist()
        publish()
    }

    /// Deletes the Account's Authorisation and Snapshot. Never touches the Provider's own
    /// CLI or app login (A6, U6).
    public func remove(_ id: UUID) throws {
        try authorisations.delete(id)
        if let account = account(id), let provider = providers.provider(for: account.provider) {
            Task { await provider.forget(account) }
        }
        accounts.removeAll { $0.id == id }
        runtime[id] = nil
        publishedStore.removeAccount(id)
        try persist()
        publish()
    }

    /// Replaces the Account's Authorisation and its creation date (U2), then fetches.
    public func reauthorise(_ id: UUID, with authorisation: String?, createdAt: Date = Date(), enteredExpiry: Date? = nil, fixtureScenario: FixtureScenario? = nil) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
        // Never logs the Authorisation itself.
        NSLog("Agent Usage: re-authorising %@ (%@), new Authorisation: %@", id.uuidString, accounts[index].provider.rawValue, authorisation == nil ? "no" : "yes")
        if let authorisation {
            try authorisations.save(authorisation, for: id)
            accounts[index].authorisationCreatedAt = createdAt
            // A new token replaces the old one's expiry, including with none.
            accounts[index].enteredAuthorisationExpiry = enteredExpiry
            // Drop the old token's reported expiry until the next fetch reports the new one.
            runtime[id]?.snapshot?.authorisationExpiresAt = nil
        }
        if let fixtureScenario { accounts[index].fixtureScenario = fixtureScenario }
        try persist()
        await refresh(id)
    }

    /// Changes a fixture Account's canned behaviour (Debug builds only use this).
    public func setFixtureScenario(_ scenario: FixtureScenario, for id: UUID) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
        accounts[index].fixtureScenario = scenario
        try persist()
        await refresh(id)
    }

    private func persist() throws {
        try accountStore.save(accounts)
    }
}
