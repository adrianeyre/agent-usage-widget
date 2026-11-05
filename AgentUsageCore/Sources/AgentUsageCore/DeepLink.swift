import Foundation

/// `agentusage://account/<id>`: tapping a widget opens the host app with that Account
/// selected (U5).
public enum DeepLink {
    public static let scheme = "agentusage"

    public static func account(_ id: UUID) -> URL {
        URL(string: "\(scheme)://account/\(id.uuidString)")!
    }

    /// The Account a link points to, or `nil` for any other link.
    public static func accountID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "account" else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}
