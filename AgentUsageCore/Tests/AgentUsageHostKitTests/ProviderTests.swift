import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageHostKit

struct StubHTTP: HTTPClient {
    let status: Int
    let body: String
    var check: @Sendable (URLRequest) -> Void = { _ in }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        check(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

struct FailingHTTP: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

/// Stands in for the `claude` CLI, answering by its first argument.
struct StubClaude: ClaudeCodeRunner {
    var usage: String
    var status = #"{"loggedIn":true,"email":"you@example.com","orgId":"org-1","orgName":"Acme","subscriptionType":"max"}"#

    func run(_ arguments: [String], home: URL) async throws -> Data {
        Data((arguments.first == "auth" ? status : usage).utf8)
    }
}

@Suite("Claude Provider (Claude Code's /usage)")
struct ClaudeProviderTests {
    let account = Account(provider: .claude, name: "Work", email: "you@example.com", emailVerified: true, organisationID: "org-1")

    static func usageJSON(_ text: String) -> String {
        let escaped = try! JSONSerialization.data(withJSONObject: ["result": text, "num_turns": 0, "total_cost_usd": 0, "local_command": "usage"])
        return String(decoding: escaped, as: UTF8.self)
    }

    // What Claude Code 2.1.318 printed on 5 November 2026.
    static let realText = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 3% used · resets Nov 5 at 4:39pm (Europe/London)
    Current week (all models): 34% used · resets Nov 5 at 3pm (Europe/London)
    Current week (Fable): 0% used · resets Nov 5 at 3pm (Europe/London)

    What's contributing to your usage?
    """

    func provider(_ stub: StubClaude) throws -> (ClaudeUsageProvider, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-homes-\(UUID().uuidString)")
        let homes = ClaudeHomes(root: root)
        try ClaudeHomes.prepare(home: homes.home(for: account.id))
        return (ClaudeUsageProvider(cli: stub, homes: homes), root)
    }

    static func london(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test("Reads Session and Weekly, with reset times in /usage's time zone")
    func parsesRealOutput() async throws {
        let (provider, root) = try provider(StubClaude(usage: Self.usageJSON(Self.realText)))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try await provider.fetch(for: account)
        #expect(snapshot.limits.map(\.name) == ["Session (5h)", "Weekly"])
        #expect(snapshot.limits.map(\.percentUsed) == [3, 34])
        let now = Self.london(2026, 11, 5, 12, 40)
        let parsed = try #require(ClaudeUsageProvider.parseUsage(Data(Self.usageJSON(Self.realText).utf8), accountID: account.id, now: now))
        #expect(parsed.limits[0].resetsAt == Self.london(2026, 11, 5, 16, 39))
        #expect(parsed.limits[1].resetsAt == Self.london(2026, 11, 5, 15))
        #expect(parsed.limits[1].windowLength == WindowLength.claudeWeekly)
    }

    @Test("A reset in January read in December is next year; a time alone is today or tomorrow")
    func resetDates() {
        let london = TimeZone(identifier: "Europe/London")
        let lateDecember = Self.london(2026, 12, 30, 20)
        #expect(ClaudeUsageProvider.resetDate("Jan 2 at 9am", timeZone: london, now: lateDecember) == Self.london(2027, 1, 2, 9))
        let noon = Self.london(2026, 11, 5, 12)
        #expect(ClaudeUsageProvider.resetDate("4:39pm", timeZone: london, now: noon) == Self.london(2026, 11, 5, 16, 39))
        #expect(ClaudeUsageProvider.resetDate("9am", timeZone: london, now: noon) == Self.london(2026, 11, 6, 9))
        #expect(ClaudeUsageProvider.resetDate("soon-ish", timeZone: london, now: noon) == nil)
    }

    @Test("A missing line or reset becomes nil, never a guessed number (R6)")
    func missingParts() throws {
        let text = "Current week (all models): 12% used\n"
        let snapshot = try #require(ClaudeUsageProvider.parseUsage(Data(Self.usageJSON(text).utf8), accountID: account.id, now: Date()))
        #expect(snapshot.limits[0].percentUsed == nil)
        #expect(snapshot.limits[1].percentUsed == 12)
        #expect(snapshot.limits[1].resetsAt == nil)
    }

    @Test("Signed out is Sign in required; otherwise unreadable output is an error")
    func signedOut() async throws {
        let summary = Self.usageJSON("Total cost: $0.0000\nUsage: 0 input, 0 output\n")
        let (out, root1) = try provider(StubClaude(usage: summary, status: #"{"loggedIn":false,"authMethod":"none"}"#))
        defer { try? FileManager.default.removeItem(at: root1) }
        await #expect(throws: UsageProviderError.authorisationRejected) { try await out.fetch(for: account) }
        let (changed, root2) = try provider(StubClaude(usage: summary))
        defer { try? FileManager.default.removeItem(at: root2) }
        await #expect(throws: UsageProviderError.unexpectedResponse("Claude Code's /usage didn't include Session or Weekly figures")) { try await changed.fetch(for: account) }
    }

    @Test("No Claude Code folder means no Authorisation")
    func noHome() async throws {
        let homes = ClaudeHomes(root: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)"))
        let provider = ClaudeUsageProvider(cli: StubClaude(usage: "{}"), homes: homes)
        await #expect(throws: UsageProviderError.authorisationMissing) { try await provider.fetch(for: account) }
    }

    @Test("auth status gives the email and organisation (A3, A5)")
    func status() throws {
        let status = try ClaudeUsageProvider.parseStatus(Data(StubClaude(usage: "").status.utf8))
        #expect(status == .init(loggedIn: true, email: "you@example.com", organisationID: "org-1", organisationName: "Acme", subscription: "max"))
    }

    @Test("Every Claude Code process runs in the Account's own folder, with no inherited token")
    func environment() {
        let home = URL(fileURLWithPath: "/tmp/agent-usage-claude/abc")
        let environment = ClaudeCLI.environment(home: home)
        #expect(environment["CLAUDE_CONFIG_DIR"] == home.path)
        #expect(environment["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
    }

    @Test("The real claude CLI, in an empty folder, says Sign in required", .enabled(if: ClaudeCLI.executable() != nil))
    func realCLISignedOut() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-real-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let homes = ClaudeHomes(root: root)
        try ClaudeHomes.prepare(home: homes.home(for: account.id))
        let provider = ClaudeUsageProvider(homes: homes)
        await #expect(throws: UsageProviderError.authorisationRejected) { try await provider.fetch(for: account) }
    }

    // MARK: The earlier status line wrapper is taken out

    func legacySetup(command: (URL) -> String, original: String?, at path: (URL) -> URL) throws -> (settings: URL, feed: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        let feed = root.appendingPathComponent("claude-feed")
        try FileManager.default.createDirectory(at: feed, withIntermediateDirectories: true)
        if let original {
            let url = path(feed)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(original.utf8).write(to: url)
        }
        let settings = root.appendingPathComponent("settings.json")
        let line = try JSONSerialization.data(withJSONObject: ["theme": "dark", "statusLine": ["type": "command", "command": command(feed)]])
        try line.write(to: settings)
        return (settings, feed, root)
    }

    func statusLine(_ url: URL) throws -> [String: Any]? {
        (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["statusLine"] as? [String: Any]
    }

    @Test("The shared-folder wrapper is replaced by the Owner's original status line")
    func restoresSharedWrapper() throws {
        let (settings, feed, root) = try legacySetup(
            command: { "'\($0.path)/agent-usage-statusline' '8b2f7899974e11e2' '/Users/me/.claude.json'" },
            original: #"{"command":"/usr/local/bin/ccstatusline","padding":0,"type":"command"}"#,
            at: { $0.appendingPathComponent("8b2f7899974e11e2/original.json") }
        )
        defer { try? FileManager.default.removeItem(at: root) }
        LegacyClaudeStatusLine.restore(settingsFiles: [settings], feedRoot: feed)
        #expect(try statusLine(settings)?["command"] as? String == "/usr/local/bin/ccstatusline")
        #expect(!FileManager.default.fileExists(atPath: feed.path))
    }

    @Test("The first version's wrapper is replaced too")
    func restoresFirstWrapper() throws {
        let id = UUID().uuidString
        let (settings, feed, root) = try legacySetup(
            command: { "'\($0.path)/agent-usage-statusline' \(id)" },
            original: #"{"command":"echo original","type":"command"}"#,
            at: { $0.appendingPathComponent("\(id).original.json") }
        )
        defer { try? FileManager.default.removeItem(at: root) }
        LegacyClaudeStatusLine.restore(settingsFiles: [settings], feedRoot: feed)
        #expect(try statusLine(settings)?["command"] as? String == "echo original")
    }

    @Test("Without the saved original, nothing is changed or deleted")
    func keepsWhenOriginalMissing() throws {
        let (settings, feed, root) = try legacySetup(
            command: { "'\($0.path)/agent-usage-statusline' 'abc' '/x'" }, original: nil, at: { $0 }
        )
        defer { try? FileManager.default.removeItem(at: root) }
        LegacyClaudeStatusLine.restore(settingsFiles: [settings], feedRoot: feed)
        #expect((try statusLine(settings)?["command"] as? String)?.contains("agent-usage-statusline") == true)
        #expect(FileManager.default.fileExists(atPath: feed.path))
    }
}

#if DEBUG
@Suite("Fixture Provider")
struct FixtureProviderTests {
    @Test("Returns canned Limits whose markers move between fetches (#18, P5)")
    func canned() async throws {
        let account = Account(provider: .fixture, name: "F", email: "f@example.com", emailVerified: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await FixtureUsageProvider(now: { start }).fetch(for: account)
        let later = try await FixtureUsageProvider(now: { start.addingTimeInterval(300) }).fetch(for: account)
        #expect(first.limits.map(\.percentUsed) == [45, 71])
        #expect(first.limits[0].resetsAt == later.limits[0].resetsAt)
        let m1 = DisplayModel.limitDisplay(first.limits[0], now: start).markerFraction!
        let m2 = DisplayModel.limitDisplay(later.limits[0], now: start.addingTimeInterval(300)).markerFraction!
        #expect(m2 > m1)
    }

    @Test("Scenarios cover Sign in required and offline")
    func scenarios() async throws {
        var account = Account(provider: .fixture, name: "F", email: "f@example.com", emailVerified: true)
        account.fixtureScenario = .signInRequired
        await #expect(throws: UsageProviderError.authorisationRejected) { try await FixtureUsageProvider().fetch(for: account) }
        account.fixtureScenario = .noActiveSession
        let snapshot = try await FixtureUsageProvider().fetch(for: account)
        #expect(snapshot.limits[0].resetsAt == nil)
    }

    @Test("Debug builds can add fixture Accounts")
    func registry() {
        #expect(ProviderRegistry.live(authorisations: InMemoryAuthorisationStore()).addableProviders == [.claude, .codex, .copilot, .fixture])
    }
}
#endif
