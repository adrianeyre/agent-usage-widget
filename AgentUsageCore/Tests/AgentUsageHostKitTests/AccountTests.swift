import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageHostKit

private func claude(_ name: String, _ email: String, org: String? = nil) -> Account {
    Account(provider: .claude, name: name, email: email, emailVerified: true, organisationID: org)
}

@Suite("Account rules")
struct AccountRulesTests {
    @Test("A name is required and trimmed (A2)")
    func nameRequired() throws {
        #expect(throws: AccountError.nameRequired) { try AccountRules.validatedName("   ", for: nil, among: []) }
        #expect(try AccountRules.validatedName("  Work ", for: nil, among: []) == "Work")
    }

    @Test("Names are unique, ignoring case (A2)")
    func nameUnique() throws {
        let work = claude("Work", "a@example.com")
        #expect(throws: AccountError.nameTaken("work")) { try AccountRules.validatedName("work", for: nil, among: [work]) }
        // Renaming an Account to its own name is fine.
        #expect(try AccountRules.validatedName("WORK", for: work.id, among: [work]) == "WORK")
    }

    @Test("Same email and organisation is a duplicate (A5, §12 #8)")
    func duplicateWithOrganisation() {
        let existing = claude("Work", "you@example.com", org: "org-1")
        let candidate = claude("Another name", "YOU@example.com", org: "org-1")
        #expect(AccountRules.duplicate(of: candidate, among: [existing]) == existing)
    }

    @Test("Same email in a different organisation is a separate Account (§10)")
    func differentOrganisation() {
        let existing = claude("Work", "you@example.com", org: "org-1")
        let candidate = claude("Personal", "you@example.com", org: "org-2")
        #expect(AccountRules.duplicate(of: candidate, among: [existing]) == nil)
    }

    @Test("Without an organisation, same email and name is a duplicate (A5, §12 #8)")
    func duplicateWithoutOrganisation() {
        let existing = claude("you@example.com", "you@example.com")
        #expect(AccountRules.duplicate(of: claude("You@Example.com", "you@example.com"), among: [existing]) == existing)
        #expect(AccountRules.duplicate(of: claude("Personal", "you@example.com"), among: [existing]) == nil)
    }

    @Test("The same email at two Providers is two Accounts (§10)")
    func differentProvider() {
        let existing = claude("x@example.com", "x@example.com")
        let fixture = Account(provider: .fixture, name: "x@example.com", email: "x@example.com", emailVerified: true)
        #expect(AccountRules.duplicate(of: fixture, among: [existing]) == nil)
    }
}

@Suite("Refresh settings")
struct RefreshSettingsTests {
    @Test("Defaults to 5 minutes, follows defaults write, never below 30 s (R1)")
    func interval() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        #expect(RefreshSettings.interval(defaults) == 300)
        defaults.set(120, forKey: RefreshSettings.intervalKey)
        #expect(RefreshSettings.interval(defaults) == 120)
        defaults.set(5, forKey: RefreshSettings.intervalKey)
        #expect(RefreshSettings.interval(defaults) == 30)
    }
}

@Suite("Deep links")
struct DeepLinkTests {
    @Test("A widget's link opens its Account (U5)")
    func roundTrip() {
        let id = UUID()
        #expect(DeepLink.accountID(from: DeepLink.account(id)) == id)
        #expect(DeepLink.accountID(from: URL(string: "https://example.com/account/\(id)")!) == nil)
    }
}

@Suite("Authorisation files")
struct AuthorisationFileTests {
    @Test("Re-authorising replaces the file rather than adding a second (U2, #22)")
    func replaceNotDuplicate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileAuthorisationStore(directory: dir)
        let id = UUID()
        try store.save("first", for: id)
        try store.save("second", for: id)
        #expect(try store.read(id) == "second")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [id.uuidString])
        try store.delete(id)
        #expect(try store.read(id) == nil)
        try store.delete(id) // deleting twice is fine
    }

    @Test("Only the Owner can read the files (700 folder, 600 file)")
    func permissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileAuthorisationStore(directory: dir)
        let id = UUID()
        try store.save("github_pat_x", for: id)
        func mode(_ path: String) throws -> Int { (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber).intValue }
        #expect(try mode(dir.path) == 0o700)
        #expect(try mode(store.url(id).path) == 0o600)
    }

    @Test("The default folder is host-only, outside what the widget can read (ADR-0004)")
    func location() {
        let path = FileAuthorisationStore().directory.path
        #expect(path.contains("/Agent Usage/host/"))
        #expect(!path.contains("/widget"))
    }
}
