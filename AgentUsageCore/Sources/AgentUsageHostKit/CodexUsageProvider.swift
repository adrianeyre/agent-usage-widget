import AgentUsageCore
import Foundation

/// Fetches a Codex Account's Limits by starting `codex app-server` against the Account's
/// own Codex home and calling `account/rateLimits/read` (ADR-0005).
///
/// Codex holds the ChatGPT login in that home, so the app never sees a token, and because
/// the app is the only program that uses the folder, Codex's rotating refresh tokens never
/// clash with another login. The Owner's everyday `~/.codex` is never used (U6).
///
/// The app-server schema is marked unstable, so every field is read defensively (§7.3).
/// The field names were checked against `codex app-server generate-json-schema` from
/// codex-cli 0.166.0 (#26).
public struct CodexUsageProvider: UsageProvider {
    let server: any CodexAppServer
    let homes: CodexHomes

    public init(server: any CodexAppServer = CodexProcessServer(), homes: CodexHomes = CodexHomes()) {
        self.server = server
        self.homes = homes
    }

    public func fetch(for account: Account) async throws -> UsageSnapshot {
        let home = homes.home(for: account.id)
        guard FileManager.default.fileExists(atPath: home.path) else { throw UsageProviderError.authorisationMissing }
        let response = try await server.call(home: home, method: "account/rateLimits/read", params: nil)
        return try Self.parseRateLimits(response, accountID: account.id, fetchedAt: Date())
    }

    /// Signs the Account's Codex home out and deletes it, which also removes a Keychain-stored
    /// login (A6). Only the app's own folder is touched.
    public func forget(_ account: Account) async {
        let home = homes.home(for: account.id)
        guard FileManager.default.fileExists(atPath: home.path) else { return }
        _ = try? await server.call(home: home, method: "account/logout", params: nil)
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Account email and plan (A3, A5)

    public struct Profile: Equatable, Sendable {
        public var email: String?
        public var planType: String?
        public var workspaceName: String?
    }

    public static func fetchProfile(home: URL, server: any CodexAppServer = CodexProcessServer()) async throws -> Profile {
        let response = try await server.call(home: home, method: "account/read", params: ["refreshToken": false])
        return try parseProfile(response)
    }

    // MARK: Parsing

    static func parseRateLimits(_ result: [String: Any], accountID: UUID, fetchedAt: Date) throws -> UsageSnapshot {
        // Prefer the `codex` bucket of the multi-bucket view, then the single-bucket view.
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        guard let bucket = (byID?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else {
            throw UsageProviderError.unexpectedResponse("rate limits response has no rateLimits")
        }
        let windows = ["primary", "secondary"].compactMap { bucket[$0] as? [String: Any] }
        let limits = windows.map { window -> LimitUsage in
            let minutes = JSONValue.number(window["windowDurationMins"])
            let length = minutes.map { $0 * 60 }
            return LimitUsage(
                name: length.map(WindowLength.name(forWindow:)) ?? "Limit",
                percentUsed: JSONValue.number(window["usedPercent"]),
                windowLength: length,
                resetsAt: JSONValue.date(window["resetsAt"])
            )
        }
        // Shortest Window first, so `5h` comes before `Weekly` (ChatGPT Pro has Weekly only, PV2).
        let ordered = limits.sorted { ($0.windowLength ?? .infinity) < ($1.windowLength ?? .infinity) }
        guard !ordered.isEmpty else {
            throw UsageProviderError.unexpectedResponse("rate limits response has no windows")
        }
        return UsageSnapshot(accountID: accountID, limits: ordered, fetchedAt: fetchedAt)
    }

    static func parseProfile(_ result: [String: Any]) throws -> Profile {
        guard let account = result["account"] as? [String: Any] else {
            throw UsageProviderError.authorisationRejected
        }
        guard account["type"] as? String == "chatgpt" else {
            throw UsageProviderError.unexpectedResponse("this Codex home isn't signed in with ChatGPT")
        }
        let email = account["email"] as? String
        return Profile(
            email: email?.isEmpty == false ? email : nil,
            planType: account["planType"] as? String,
            workspaceName: account["workspaceName"] as? String
        )
    }
}

/// Where each Codex Account's home lives: `Application Support/Agent Usage/codex/<id>/`,
/// a folder only the app uses (ADR-0005). It isn't under `widget/`, so the widget can't read it.
public struct CodexHomes: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.supportDirectory.appendingPathComponent("codex", isDirectory: true)) {
        self.root = root
    }

    public func home(for accountID: UUID) -> URL {
        root.appendingPathComponent(accountID.uuidString, isDirectory: true)
    }

    /// Creates the home with Codex set to keep its login in the Keychain, not `auth.json` (#26).
    public func prepare(_ accountID: UUID) throws -> URL {
        try Self.prepare(home: home(for: accountID))
    }

    @discardableResult
    public static func prepare(home: URL) throws -> URL {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let config = home.appendingPathComponent("config.toml")
        if !FileManager.default.fileExists(atPath: config.path) {
            try Data(configTOML.utf8).write(to: config, options: .atomic)
        }
        return home
    }

    static let configTOML = """
    # Written by Agent Usage. This Codex home belongs to one Agent Usage Account (ADR-0005).
    cli_auth_credentials_store = "keyring"
    check_for_update_on_startup = false

    [analytics]
    enabled = false

    """
}

/// One JSON-RPC call to `codex app-server` for a Codex home. Tests stand in for the process.
public protocol CodexAppServer: Sendable {
    /// Returns the call's `result`. A JSON-RPC error saying authentication is required
    /// throws `authorisationRejected` (`Sign in required`, R5).
    func call(home: URL, method: String, params: [String: Any]?) async throws -> [String: Any]
}

/// Runs `codex app-server` over stdio for each call: `initialize`, `initialized`, then the call.
public struct CodexProcessServer: CodexAppServer {
    public var timeout: TimeInterval = 30

    public init() {}

    public func call(home: URL, method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let executable = CodexCLI.executable() else {
            throw UsageProviderError.unexpectedResponse("the codex CLI isn't installed")
        }
        let timeout = timeout
        return try await Task.detached {
            try Self.run(executable: executable, home: home, method: method, params: params, timeout: timeout)
        }.value
    }

    static func run(executable: URL, home: URL, method: String, params: [String: Any]?, timeout: TimeInterval) throws -> [String: Any] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = CodexCLI.environment(home: home)
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            throw UsageProviderError.unexpectedResponse("couldn't start codex: \(error.localizedDescription)")
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        let lines = LineReader(handle: output.fileHandleForReading, deadline: Date().addingTimeInterval(timeout))
        func response(to id: Int) throws -> [String: Any] {
            while let line = lines.next() {
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (message["id"] as? NSNumber)?.intValue == id else { continue }
                return message
            }
            throw UsageProviderError.network("codex app-server didn't answer \(method)")
        }

        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "agent-usage", "version": AppInfo.version]]])
        let initialised = try response(to: 1)
        if initialised["error"] != nil { throw UsageProviderError.unexpectedResponse("codex app-server refused initialize") }
        try send(["method": "initialized"])
        var request: [String: Any] = ["id": 2, "method": method]
        if let params { request["params"] = params }
        try send(request)
        return try Self.result(of: try response(to: 2))
    }

    static func result(of message: [String: Any]) throws -> [String: Any] {
        if let error = message["error"] as? [String: Any] {
            let text = (error["message"] as? String ?? "").lowercased()
            if text.contains("auth") || text.contains("login") || text.contains("sign in") {
                throw UsageProviderError.authorisationRejected
            }
            throw UsageProviderError.unexpectedResponse("codex: \(error["message"] as? String ?? "error")")
        }
        return message["result"] as? [String: Any] ?? [:]
    }
}

/// Reads newline-delimited messages from a pipe until a deadline.
final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let deadline: Date
    private var buffer = Data()

    init(handle: FileHandle, deadline: Date) {
        self.handle = handle
        self.deadline = deadline
    }

    func next() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            guard Date() < deadline else { return nil }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

/// Finding and running the `codex` CLI. A login item starts with a minimal `PATH`, so the
/// usual install locations are searched as well.
public enum CodexCLI {
    static var searchPaths: [String] {
        let home = AppPaths.realHomeDirectory.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "/usr/bin"]
    }

    public static func executable() -> URL? {
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in fromPath + searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The environment for every Codex process the app starts: always the Account's own home.
    public static func environment(home: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        environment["PATH"] = (searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        return environment
    }
}
