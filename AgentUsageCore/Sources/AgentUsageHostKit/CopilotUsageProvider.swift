import AgentUsageCore
import Foundation

/// Fetches a Copilot Account's Monthly credits with its fine-grained personal access token,
/// kept in the app's private Authorisation file (U1, ADR-0010).
///
/// The source is `GET https://api.github.com/copilot_internal/user`, the endpoint Copilot's own
/// editor extensions use. It's undocumented (ADR-0006): the documented billing API reports
/// credits used but not the monthly allowance, so it can't give a percentage (#27).
public struct CopilotUsageProvider: UsageProvider {
    public static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
    public static let userURL = URL(string: "https://api.github.com/user")!
    public static let emailsURL = URL(string: "https://api.github.com/user/emails")!
    /// Where Re-authorise sends the Owner to make a replacement token (U2).
    public static let newTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!
    static let expiryHeader = "github-authentication-token-expiration"

    /// The quota buckets, in display order, with the name each is shown under. Copilot plans
    /// that bill in credits report them in `premium_interactions`; Copilot Free also has
    /// separate monthly chat and completion allowances.
    static let buckets: [(id: String, name: String)] = [
        ("premium_interactions", "Monthly credits"),
        ("chat", "Chat"),
        ("completions", "Completions"),
    ]

    let authorisations: any AuthorisationStore
    let http: any HTTPClient

    public init(authorisations: any AuthorisationStore, http: any HTTPClient = URLSession.shared) {
        self.authorisations = authorisations
        self.http = http
    }

    public func fetch(for account: Account) async throws -> UsageSnapshot {
        guard let token = try authorisations.read(account.id), !token.isEmpty else {
            throw UsageProviderError.authorisationMissing
        }
        let (data, response) = try await Self.get(Self.usageURL, token: token, http: http)
        var snapshot = try Self.parseUsage(data, accountID: account.id, fetchedAt: Date())
        snapshot.authorisationExpiresAt = Self.expiry(from: response)
        return snapshot
    }

    // MARK: Username and email (PV6)

    public struct Profile: Equatable, Sendable {
        public var login: String
        public var email: String?
        public var userID: String?
        public var expiresAt: Date?

        /// `@username`, plus the primary email when the token can read it (PV6).
        public var accountEmail: String {
            if let email, !email.isEmpty { return "@\(login) · \(email)" }
            return "@\(login)"
        }
    }

    public static func fetchProfile(token: String, http: any HTTPClient = URLSession.shared) async throws -> Profile {
        let (data, response) = try await get(userURL, token: token, http: http)
        var profile = try parseUser(data)
        profile.expiresAt = expiry(from: response)
        if profile.email == nil, let (emails, _) = try? await get(emailsURL, token: token, http: http) {
            profile.email = parsePrimaryEmail(emails)
        }
        return profile
    }

    // MARK: Parsing (tolerant: missing fields become nil, §7.3)

    static func parseUsage(_ data: Data, accountID: UUID, fetchedAt: Date) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.unexpectedResponse("Copilot response isn't a JSON object")
        }
        guard let snapshots = root["quota_snapshots"] as? [String: Any] else {
            throw UsageProviderError.unexpectedResponse("Copilot response has no quota_snapshots")
        }
        let reset = JSONValue.date(root["quota_reset_date_utc"]) ?? date(fromDay: root["quota_reset_date"])
        let window = reset.map(WindowLength.utcMonth(endingAt:))

        let limits = buckets.compactMap { bucket -> LimitUsage? in
            guard let quota = snapshots[bucket.id] as? [String: Any] else { return nil }
            // Skip buckets the plan doesn't have, or that are unlimited: no bar can show them.
            if quota["unlimited"] as? Bool == true { return nil }
            let entitlement = JSONValue.number(quota["entitlement"])
            guard let entitlement, entitlement > 0 else { return nil }
            return LimitUsage(name: bucket.name, percentUsed: percentUsed(quota, entitlement: entitlement), windowLength: window, resetsAt: reset)
        }
        guard !limits.isEmpty else {
            throw UsageProviderError.unexpectedResponse("Copilot reports no limited quota for this Account")
        }
        return UsageSnapshot(accountID: accountID, limits: limits, fetchedAt: fetchedAt)
    }

    /// From the credits used where reported, otherwise from `percent_remaining`. Never invented (R6).
    static func percentUsed(_ quota: [String: Any], entitlement: Double) -> Double? {
        if let remaining = JSONValue.number(quota["remaining"] ?? quota["quota_remaining"]) {
            return max(0, (entitlement - remaining) / entitlement * 100)
        }
        if let percentRemaining = JSONValue.number(quota["percent_remaining"]) {
            return max(0, 100 - percentRemaining)
        }
        return nil
    }

    static func date(fromDay value: Any?) -> Date? {
        guard let day = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    static func parseUser(_ data: Data) throws -> Profile {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = root["login"] as? String, !login.isEmpty else {
            throw UsageProviderError.unexpectedResponse("GitHub user has no login")
        }
        let email = root["email"] as? String
        let id = (root["id"] as? NSNumber)?.stringValue
        return Profile(login: login, email: email?.isEmpty == false ? email : nil, userID: id)
    }

    static func parsePrimaryEmail(_ data: Data) -> String? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return list.first { $0["primary"] as? Bool == true }?["email"] as? String
    }

    /// GitHub sends e.g. `2027-11-05 10:00:00 UTC` (or `+0000`) for tokens with an expiry (U3).
    static func expiry(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: expiryHeader) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss zzz", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    // MARK: Requests

    static func get(_ url: URL, token: String, http: any HTTPClient) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AgentUsage/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401: throw UsageProviderError.authorisationRejected
        // 403 and 404 also come back when the token lacks a permission or the plan has no Copilot.
        case 403, 404: throw UsageProviderError.authorisationRejected
        default: throw UsageProviderError.unexpectedResponse("HTTP \(response.statusCode)")
        }
    }
}
