import Foundation
import Testing
@testable import AgentUsageCore

private let hour: TimeInterval = 60 * 60
private let day: TimeInterval = 24 * hour

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

/// Thursday 5 November 2026, 10:00 London time.
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!

private func account(
    limits: [LimitUsage],
    fetchedAgo: TimeInterval = 60,
    signInRequired: Bool = false,
    expiresAt: Date? = nil
) -> PublishedAccount {
    let id = UUID()
    return PublishedAccount(
        id: id, provider: .claude, name: "Work", email: "you@example.com",
        authorisationExpiresAt: expiresAt, signInRequired: signInRequired,
        snapshot: UsageSnapshot(accountID: id, limits: limits, fetchedAt: now.addingTimeInterval(-fetchedAgo))
    )
}

private let session = LimitUsage(name: "Session (5h)", percentUsed: 45, windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(2 * hour))
private let weekly = LimitUsage(name: "Weekly", percentUsed: 71, windowLength: WindowLength.claudeWeekly, resetsAt: calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!)

@Suite("Display model")
struct DisplayModelTests {
    @Test("The worked example: Session 45% on pace, Weekly 71% over pace")
    func workedExample() throws {
        let card = DisplayModel.card(for: account(limits: [session, weekly]), now: now, calendar: calendar)
        #expect(card.limits.count == 2)
        let s = card.limits[0]
        #expect(s.percentText == "45%")
        #expect(s.paceLabel == "on pace")
        #expect(s.band == .green)
        #expect(s.detailText == "resets in 2h 00m")
        let w = card.limits[1]
        #expect(w.percentText == "71%")
        #expect(w.detailText == "resets Mon 09:00")
        #expect(w.band == .red) // marker at 43%
        #expect(w.paceLabel == "over +28%")
        #expect(card.status == .ok)
        #expect(card.updatedText == "Updated 1m ago")
    }

    @Test("Usage at or above 100% shows a full red bar and Limit reached (§10)")
    func limitReached() {
        let limit = LimitUsage(name: "Session (5h)", percentUsed: 104, windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(90 * 60))
        let display = DisplayModel.limitDisplay(limit, now: now, calendar: calendar)
        #expect(display.fillFraction == 1)
        #expect(display.band == .red)
        #expect(display.detailText == "Limit reached · resets in 1h 30m")
        #expect(display.compactText == "Limit reached")
        #expect(display.isLimitReached)
    }

    @Test("No Session reset time: empty bar, no marker, No active session (P6)")
    func noActiveSession() {
        let limit = LimitUsage(name: "Session (5h)", percentUsed: 0, windowLength: WindowLength.claudeSession, resetsAt: nil)
        let display = DisplayModel.limitDisplay(limit, now: now, calendar: calendar)
        #expect(display.fillFraction == 0)
        #expect(display.markerFraction == nil)
        #expect(display.detailText == "No active session")
        #expect(display.paceLabel == nil)
    }

    @Test("A reset in the past puts the marker at 0% and shows Stale (§10)")
    func pastReset() {
        let past = LimitUsage(name: "Session (5h)", percentUsed: 30, windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(-60))
        let card = DisplayModel.card(for: account(limits: [past]), now: now, calendar: calendar)
        #expect(card.limits[0].markerFraction == 0)
        #expect(card.isStale)
        #expect(card.status == .stale)
    }

    @Test("Only the first two Limits are shown, in the Provider's order (§10)")
    func extraLimits() {
        let third = LimitUsage(name: "Opus", percentUsed: 5, windowLength: nil, resetsAt: nil)
        let card = DisplayModel.card(for: account(limits: [session, weekly, third]), now: now, calendar: calendar)
        #expect(card.limits.map(\.name) == ["Session (5h)", "Weekly"])
    }

    @Test("A Limit without a Window length shows bar and % only (P0)")
    func noWindow() {
        let limit = LimitUsage(name: "Credits", percentUsed: 40, windowLength: nil, resetsAt: now.addingTimeInterval(3 * day))
        let display = DisplayModel.limitDisplay(limit, now: now, calendar: calendar)
        #expect(display.markerFraction == nil)
        #expect(display.paceLabel == nil)
        #expect(display.band == .neutral)
        #expect(display.fillFraction == 0.4)
        #expect(display.percentText == "40%")
    }

    @Test("A missing figure shows a dash, never a number (R6)")
    func missingFigure() {
        let limit = LimitUsage(name: "Weekly", percentUsed: nil, windowLength: WindowLength.claudeWeekly, resetsAt: now.addingTimeInterval(day))
        let display = DisplayModel.limitDisplay(limit, now: now, calendar: calendar)
        #expect(display.percentText == "—")
        #expect(display.fillFraction == 0)
        #expect(display.paceLabel == nil)
    }

    @Test("Sign in required shows no bars instead of zeros (R5)")
    func signInRequired() {
        let card = DisplayModel.card(for: account(limits: [session, weekly], signInRequired: true), now: now, calendar: calendar)
        #expect(card.limits.isEmpty)
        #expect(card.signInRequired)
        #expect(card.status == .signInRequired)
    }

    @Test("35 minutes without a fetch is Stale, and the marker keeps moving (§12 #5)")
    func staleAfterThirtyMinutes() {
        let fresh = account(limits: [session], fetchedAgo: 29 * 60)
        #expect(!DisplayModel.card(for: fresh, now: now, calendar: calendar).isStale)

        let old = account(limits: [session], fetchedAgo: 35 * 60)
        let card = DisplayModel.card(for: old, now: now, calendar: calendar)
        #expect(card.isStale)
        #expect(card.status == .stale)
        let later = DisplayModel.card(for: old, now: now.addingTimeInterval(5 * 60), calendar: calendar)
        #expect(later.limits[0].markerFraction! > card.limits[0].markerFraction!)
    }

    @Test("Within 7 days of expiry shows Re-authorise by <date> (§12 #9)")
    func reauthoriseWarning() {
        let expiry = now.addingTimeInterval(6 * day)
        let card = DisplayModel.card(for: account(limits: [session], expiresAt: expiry), now: now, calendar: calendar)
        #expect(card.reauthoriseText == "Re-authorise by 11 Nov")
        #expect(card.status == .reauthoriseBy(expiry))

        let farOff = DisplayModel.card(for: account(limits: [session], expiresAt: now.addingTimeInterval(8 * day)), now: now, calendar: calendar)
        #expect(farOff.reauthoriseText == nil)
        #expect(farOff.status == .ok)
    }

    @Test("No Account chosen shows Choose an Account (§6.1)")
    func chooseAccount() {
        #expect(DisplayModel.content(for: nil, now: now) == .chooseAccount)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func durations() {
        #expect(UsageFormatting.duration(2 * hour + 14 * 60) == "2h 14m")
        #expect(UsageFormatting.duration(14 * 60) == "14m")
        #expect(UsageFormatting.duration(20) == "1m")
        #expect(UsageFormatting.duration(0) == "<1m")
    }

    @Test func updated() {
        #expect(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-20), now: now) == "Updated just now")
        #expect(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-3 * 60), now: now) == "Updated 3m ago")
        #expect(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-3 * hour), now: now) == "Updated 3h ago")
        #expect(UsageFormatting.updatedText(fetchedAt: nil, now: now) == "Not updated yet")
    }

    @Test func percents() {
        #expect(UsageFormatting.percentText(42.4) == "42%")
        #expect(UsageFormatting.percentText(nil) == "—")
    }
}

@Suite("Published files")
struct PublishedStoreTests {
    @Test("Numbered widgets show the Account at their position (§6.1, ADR-0009)")
    func slots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("slots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PublishedStore(root: root)
        let a = PublishedAccount(id: UUID(), provider: .claude, name: "A", email: "a@x.com", emailVerified: true, authorisationExpiresAt: nil, signInRequired: false, snapshot: nil)
        var b = a
        b.id = UUID()
        b.name = "B"
        try store.publish([a, b])
        #expect(store.account(atSlot: 1)?.name == "A")
        #expect(store.account(atSlot: 2)?.name == "B")
        #expect(store.account(atSlot: 3) == nil)
        #expect(store.account(atSlot: 0) == nil)
        try store.publish([b, a])
        #expect(store.account(atSlot: 1)?.name == "B", "moving an Account changes which widget shows it")
    }

    @Test("Publishing writes the index in order and removes deleted Accounts' files (A6)")
    func publishAndRemove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PublishedStore(root: root)
        let a = account(limits: [session])
        var b = account(limits: [weekly])
        b.name = "Personal"

        try store.publish([b, a])
        #expect(store.readIndex().accounts.map(\.id) == [b.id, a.id])
        #expect(store.readAccount(a.id) == a)

        try store.publish([b])
        #expect(store.readAccount(a.id) == nil)
        #expect(store.readIndex().accounts.map(\.id) == [b.id])
    }

    @Test("A missing index reads as no Accounts")
    func missingIndex() {
        let store = PublishedStore(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(store.readIndex().accounts.isEmpty)
    }

    @Test("Published files never hold an Authorisation")
    func noSecrets() throws {
        let data = try PublishedStore.encoder.encode(account(limits: [session]))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.lowercased().contains("token"))
        #expect(!json.lowercased().contains("authorisation\""))
    }

    @Test("The widget entitlement path matches the support folder")
    func supportPath() {
        #expect(AppPaths.supportDirectory.path.hasSuffix("/Library/Application Support/Agent Usage"))
        #expect(AppPaths.homeRelativeSupportPath == "/Library/Application Support/Agent Usage/")
    }
}
