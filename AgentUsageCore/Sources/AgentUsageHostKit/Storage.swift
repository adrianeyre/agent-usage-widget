import AgentUsageCore
import Foundation

/// Keeps the ordered Account list (no Authorisations) in `host/accounts.json`.
public protocol AccountStore: Sendable {
    func load() -> [Account]
    func save(_ accounts: [Account]) throws
}

public struct FileAccountStore: AccountStore {
    public let url: URL

    public init(url: URL = AppPaths.hostDirectory.appendingPathComponent("accounts.json")) {
        self.url = url
    }

    public func load() -> [Account] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? PublishedStore.decoder.decode([Account].self, from: data)) ?? []
    }

    public func save(_ accounts: [Account]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PublishedStore.encoder.encode(accounts).write(to: url, options: .atomic)
    }
}

/// Where each Account's Authorisation lives: only in storage the app owns (U6, ADR-0003).
public protocol AuthorisationStore: Sendable {
    /// Saves or replaces the Account's Authorisation. Never creates a second item.
    func save(_ secret: String, for accountID: UUID) throws
    func read(_ accountID: UUID) throws -> String?
    func delete(_ accountID: UUID) throws
}

/// Each Account's Authorisation in its own file, `host/authorisations/<id>`, readable only by
/// the Owner (folder 700, file 600). The widget's sandbox exception doesn't cover `host/`.
///
/// Not the login Keychain: a self-signed app's Keychain items are tied to its exact build (a
/// `cdhash:` partition), so every update asked for the login-keychain password before the
/// token could be read. The Data Protection keychain needs a Team ID (-34018). See #17 and
/// ADR-0010. The only secret stored is a Copilot token with *Plan: read*.
public struct FileAuthorisationStore: AuthorisationStore {
    public let directory: URL

    public init(directory: URL = AppPaths.hostDirectory.appendingPathComponent("authorisations", isDirectory: true)) {
        self.directory = directory
    }

    func url(_ accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString)
    }

    public func save(_ secret: String, for accountID: UUID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Write to a private temporary file, then move it over the old one (replaced, never duplicated).
        let temporary = directory.appendingPathComponent(".\(accountID.uuidString).\(UUID().uuidString)")
        guard fm.createFile(atPath: temporary.path, contents: Data(secret.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try fm.replaceItemAt(url(accountID), withItemAt: temporary)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(accountID).path)
    }

    public func read(_ accountID: UUID) throws -> String? {
        guard let data = FileManager.default.contents(atPath: url(accountID).path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func delete(_ accountID: UUID) throws {
        do {
            try FileManager.default.removeItem(at: url(accountID))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }
}

/// For tests and previews.
public final class InMemoryAuthorisationStore: AuthorisationStore, @unchecked Sendable {
    private var items: [UUID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ secret: String, for accountID: UUID) throws {
        lock.withLock { items[accountID] = secret }
    }

    public func read(_ accountID: UUID) throws -> String? {
        lock.withLock { items[accountID] }
    }

    public func delete(_ accountID: UUID) throws {
        _ = lock.withLock { items.removeValue(forKey: accountID) }
    }

    public var count: Int { lock.withLock { items.count } }
}

/// The refresh interval, changeable with
/// `defaults write com.adrianeyre.AgentUsage RefreshInterval -int 120` (R1).
public enum RefreshSettings {
    public static let intervalKey = "RefreshInterval"
    public static let defaultInterval: TimeInterval = 5 * 60
    public static let minimumInterval: TimeInterval = 30

    public static func interval(_ defaults: UserDefaults = .standard) -> TimeInterval {
        let value = defaults.double(forKey: intervalKey)
        guard value > 0 else { return defaultInterval }
        return max(minimumInterval, value)
    }
}
