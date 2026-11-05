import Foundation

/// Where the host app keeps its files: `~/Library/Application Support/Agent Usage/`.
///
/// The sandboxed widget reads the `widget/` folder through the read-only
/// `temporary-exception.files.home-relative-path.read-only` entitlement for
/// `/Library/Application Support/Agent Usage/` (ADR-0004). Inside the sandbox,
/// `FileManager`'s home directory is the container, so the real home comes from the
/// password database.
public enum AppPaths {
    public static let folderName = "Agent Usage"
    /// The path the widget's entitlement grants, relative to the home directory.
    public static let homeRelativeSupportPath = "/Library/Application Support/\(folderName)/"

    public static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var supportDirectory: URL {
        realHomeDirectory.appendingPathComponent(String(homeRelativeSupportPath.dropFirst()), isDirectory: true)
    }

    /// Files the widget reads.
    public static var widgetDirectory: URL {
        supportDirectory.appendingPathComponent("widget", isDirectory: true)
    }

    /// Files only the host app reads.
    public static var hostDirectory: URL {
        supportDirectory.appendingPathComponent("host", isDirectory: true)
    }
}

/// Reads and writes the files the widget draws from:
///
/// ```
/// widget/index.json            the Account picker, in Manage Accounts order
/// widget/accounts/<id>.json    one PublishedAccount (with its Snapshot) per Account
/// ```
///
/// The host app writes; the widget only reads.
/// How many numbered widgets the gallery offers (§6.1, ADR-0009).
public enum WidgetSlots {
    public static let count = 6
}

public struct PublishedStore: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.widgetDirectory) {
        self.root = root
    }

    var indexURL: URL { root.appendingPathComponent("index.json") }
    var accountsDirectory: URL { root.appendingPathComponent("accounts", isDirectory: true) }

    func accountURL(_ id: UUID) -> URL {
        accountsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: Reading (widget and host)

    public func readIndex() -> PublishedIndex {
        (try? read(PublishedIndex.self, from: indexURL)) ?? PublishedIndex(accounts: [])
    }

    /// `nil` when the Account was removed or hasn't been published yet.
    public func readAccount(_ id: UUID) -> PublishedAccount? {
        try? read(PublishedAccount.self, from: accountURL(id))
    }

    /// The Account a numbered widget shows: the `slot`th in Manage Accounts order, from 1
    /// (§6.1, ADR-0009). `nil` when there are fewer Accounts than that.
    public func account(atSlot slot: Int) -> PublishedAccount? {
        let accounts = readIndex().accounts
        guard slot >= 1, slot <= accounts.count else { return nil }
        return readAccount(accounts[slot - 1].id)
    }

    // MARK: Writing (host only)

    /// Writes every Account and the index, and deletes files for Accounts that are gone (A6).
    public func publish(_ accounts: [PublishedAccount]) throws {
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
        for account in accounts {
            try write(account, to: accountURL(account.id))
        }
        try write(PublishedIndex(accounts: accounts.map(PublishedAccountSummary.init)), to: indexURL)

        let keep = Set(accounts.map { "\($0.id.uuidString).json" })
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: accountsDirectory.path)) ?? []
        for file in existing where file.hasSuffix(".json") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: accountsDirectory.appendingPathComponent(file))
        }
    }

    public func removeAccount(_ id: UUID) {
        try? FileManager.default.removeItem(at: accountURL(id))
    }

    // MARK: Helpers

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try Self.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Fractional seconds, so a Snapshot reads back exactly as it was written.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: true)))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }()
}
