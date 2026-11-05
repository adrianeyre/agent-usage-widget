import AgentUsageCore
import Foundation

/// Fetches a Claude Account's Session and Weekly Limits by running Claude Code's own `/usage`
/// command in a Claude Code configuration folder that belongs to the Account and is owned by
/// the app (ADR-0011, the same pattern as Codex in ADR-0005).
///
/// - **Sign-in** happens in Agent Usage: Add Account and Re-authorise run
///   `claude auth login --claudeai` with `CLAUDE_CONFIG_DIR` set to the Account's folder.
///   Claude Code keeps that login in its own Keychain item (`Claude Code-credentials-<hash>`)
///   and refreshes it itself. The app never reads a token (U6), and the Owner's everyday
///   `~/.claude` is never used.
/// - **Usage** comes from `claude -p /usage --output-format json`, which Claude Code answers
///   locally (no model request, nothing spent: `num_turns` 0, `total_cost_usd` 0).
///
/// The figures are read from `/usage`'s human-readable text, so a Claude Code update could
/// change the wording. Lines that can't be read become `nil`, never guessed numbers (R6, §7.3).
public struct ClaudeUsageProvider: UsageProvider {
    let cli: any ClaudeCodeRunner
    let homes: ClaudeHomes

    public init(cli: any ClaudeCodeRunner = ClaudeCodeProcess(), homes: ClaudeHomes = ClaudeHomes()) {
        self.cli = cli
        self.homes = homes
    }

    public func fetch(for account: Account) async throws -> UsageSnapshot {
        let home = homes.home(for: account.id)
        guard FileManager.default.fileExists(atPath: home.path) else { throw UsageProviderError.authorisationMissing }
        let output = try await cli.run(["-p", "/usage", "--output-format", "json"], home: home)
        let now = Date()
        if let snapshot = Self.parseUsage(output, accountID: account.id, now: now) {
            return snapshot
        }
        // No usage lines: signed out, or Claude Code changed its wording.
        if let status = try? await Self.status(home: home, cli: cli), status.loggedIn == false {
            throw UsageProviderError.authorisationRejected
        }
        throw UsageProviderError.unexpectedResponse("Claude Code's /usage didn't include Session or Weekly figures")
    }

    /// Signs the Account's folder out, which deletes Claude Code's Keychain item for it, then
    /// deletes the folder (A6). Only the app's own folder is touched.
    public func forget(_ account: Account) async {
        let home = homes.home(for: account.id)
        guard FileManager.default.fileExists(atPath: home.path) else { return }
        _ = try? await cli.run(["auth", "logout"], home: home)
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Account email and organisation (A3, A5)

    public struct Status: Equatable, Sendable {
        public var loggedIn: Bool
        public var email: String?
        public var organisationID: String?
        public var organisationName: String?
        public var subscription: String?
    }

    public static func status(home: URL, cli: any ClaudeCodeRunner = ClaudeCodeProcess()) async throws -> Status {
        let output = try await cli.run(["auth", "status", "--json"], home: home)
        return try parseStatus(output)
    }

    static func parseStatus(_ data: Data) throws -> Status {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.unexpectedResponse("claude auth status isn't JSON")
        }
        func text(_ key: String) -> String? {
            (root[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return Status(
            loggedIn: root["loggedIn"] as? Bool ?? false,
            email: text("email"),
            organisationID: text("orgId"),
            organisationName: text("orgName"),
            subscription: text("subscriptionType")
        )
    }

    // MARK: Parsing /usage

    /// `nil` when neither the Session nor the Weekly line is there.
    static func parseUsage(_ data: Data, accountID: UUID, now: Date) -> UsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["result"] as? String else { return nil }
        let session = line(in: text, startingWith: "Current session:", now: now)
        let weekly = line(in: text, startingWith: "Current week (all models):", now: now)
        guard session != nil || weekly != nil else { return nil }
        return UsageSnapshot(
            accountID: accountID,
            limits: [
                LimitUsage(name: "Session (5h)", percentUsed: session?.percent, windowLength: WindowLength.claudeSession, resetsAt: session?.resetsAt),
                LimitUsage(name: "Weekly", percentUsed: weekly?.percent, windowLength: WindowLength.claudeWeekly, resetsAt: weekly?.resetsAt),
            ],
            fetchedAt: now
        )
    }

    /// Reads e.g. `Current session: 3% used · resets Nov 5 at 4:39pm (Europe/London)`.
    static func line(in text: String, startingWith label: String, now: Date) -> (percent: Double?, resetsAt: Date?)? {
        guard let line = text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix(label) }) else {
            return nil
        }
        let rest = String(line.dropFirst(label.count))
        let percent = rest.firstMatch(of: #/([0-9]+(?:\.[0-9]+)?)%\s*used/#).flatMap { Double($0.1) }
        var resetsAt: Date?
        if let match = rest.firstMatch(of: #/resets\s+(.+?)\s*\(([^)]+)\)/#) {
            resetsAt = resetDate(String(match.1), timeZone: TimeZone(identifier: String(match.2)), now: now)
        } else if let match = rest.firstMatch(of: #/resets\s+(.+)$/#) {
            resetsAt = resetDate(String(match.1), timeZone: nil, now: now)
        }
        return (percent, resetsAt)
    }

    /// `Nov 5 at 4:39pm`, `Nov 5 at 3pm`, `4:39pm` or `Nov 5`, in the time zone `/usage` names.
    static func resetDate(_ text: String, timeZone: TimeZone?, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let withDay = ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d h:mma", "MMM d ha", "MMM d"]
        let timeOnly = ["h:mma", "ha"]
        for format in withDay {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: cleaned) else { continue }
            // No year is given: take the one that puts the reset nearest to now.
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            let year = calendar.component(.year, from: now)
            let candidates = [year - 1, year, year + 1].compactMap { y -> Date? in
                var c = parts
                c.year = y
                return calendar.date(from: c)
            }
            return candidates.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
        }
        for format in timeOnly {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: cleaned) else { continue }
            let time = calendar.dateComponents([.hour, .minute], from: parsed)
            guard let today = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now) else { return nil }
            return today < now.addingTimeInterval(-60) ? calendar.date(byAdding: .day, value: 1, to: today) : today
        }
        return nil
    }
}

/// Where each Claude Account's Claude Code folder lives: `Application Support/Agent Usage/claude/<id>/`.
/// It isn't under `widget/`, so the widget can't read it.
public struct ClaudeHomes: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.supportDirectory.appendingPathComponent("claude", isDirectory: true)) {
        self.root = root
    }

    public func home(for accountID: UUID) -> URL {
        root.appendingPathComponent(accountID.uuidString, isDirectory: true)
    }

    @discardableResult
    public static func prepare(home: URL) throws -> URL {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return home
    }
}

/// Runs the `claude` CLI against one Account's folder. Tests stand in for the process.
public protocol ClaudeCodeRunner: Sendable {
    func run(_ arguments: [String], home: URL) async throws -> Data
}

public struct ClaudeCodeProcess: ClaudeCodeRunner {
    public var timeout: TimeInterval = 60

    public init() {}

    public func run(_ arguments: [String], home: URL) async throws -> Data {
        guard let executable = ClaudeCLI.executable() else {
            throw UsageProviderError.unexpectedResponse("the claude CLI isn't installed")
        }
        let timeout = timeout
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ClaudeCLI.environment(home: home)
            // Run inside the Account's own folder, so Claude Code never looks at a project.
            process.currentDirectoryURL = home
            let output = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                throw UsageProviderError.unexpectedResponse("couldn't start claude: \(error.localizedDescription)")
            }
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            return data
        }.value
    }
}

/// Finding and running the `claude` CLI. A login item starts with a minimal `PATH`, so the
/// usual install locations are searched as well.
public enum ClaudeCLI {
    static var searchPaths: [String] {
        let home = AppPaths.realHomeDirectory.path
        return ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
    }

    public static func executable() -> URL? {
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in searchPaths + fromPath {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The environment for every Claude Code process the app starts: always the Account's own folder.
    public static func environment(home: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CONFIG_DIR"] = home.path
        environment["PATH"] = (searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        // Never inherit a token or API key meant for something else.
        for key in ["CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"] {
            environment.removeValue(forKey: key)
        }
        return environment
    }
}

/// Removes the status line wrapper an earlier version put in front of the Owner's Claude Code
/// status line (ADR-0008, superseded by ADR-0011), putting the original back exactly.
public enum LegacyClaudeStatusLine {
    public static var defaultFeedRoot: URL { AppPaths.hostDirectory.appendingPathComponent("claude-feed", isDirectory: true) }

    /// Restores every settings file that still runs the wrapper, then deletes the feed files.
    public static func restore(
        settingsFiles: [URL] = [AppPaths.realHomeDirectory.appendingPathComponent(".claude/settings.json")],
        feedRoot: URL = defaultFeedRoot
    ) {
        let script = feedRoot.appendingPathComponent("agent-usage-statusline").path
        var keepFeedFiles = false
        for url in settingsFiles {
            guard let data = try? Data(contentsOf: url),
                  var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let command = (settings["statusLine"] as? [String: Any])?["command"] as? String,
                  command.contains(script) else { continue }
            // `'<script>' '<key>' '<meta>'` (shared folders) or `'<script>' <account-id>` (first version).
            let words = command.dropFirst(script.count + 2).split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            var original: [String: Any]?
            if let word = words.first {
                for candidate in [feedRoot.appendingPathComponent(word).appendingPathComponent("original.json"),
                                  feedRoot.appendingPathComponent("\(word).original.json")] {
                    if let value = (try? JSONSerialization.jsonObject(with: Data(contentsOf: candidate))) as? [String: Any] {
                        original = value
                        break
                    }
                }
            }
            // Without the saved original, change nothing rather than lose the Owner's status line.
            guard let original else {
                keepFeedFiles = true
                continue
            }
            if original.isEmpty {
                settings.removeValue(forKey: "statusLine")
            } else {
                settings["statusLine"] = original
            }
            if let out = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? out.write(to: url, options: .atomic)
            }
        }
        if !keepFeedFiles { try? FileManager.default.removeItem(at: feedRoot) }
    }
}
