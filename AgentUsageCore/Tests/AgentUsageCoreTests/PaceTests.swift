import Foundation
import Testing
@testable import AgentUsageCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 60 * 60
private let day: TimeInterval = 24 * hour

private func session(_ used: Double?, resetIn: TimeInterval?) -> LimitUsage {
    LimitUsage(name: "Session (5h)", percentUsed: used, windowLength: WindowLength.claudeSession, resetsAt: resetIn.map { now.addingTimeInterval($0) })
}

private func weekly(_ used: Double?, resetIn: TimeInterval?) -> LimitUsage {
    LimitUsage(name: "Weekly", percentUsed: used, windowLength: WindowLength.claudeWeekly, resetsAt: resetIn.map { now.addingTimeInterval($0) })
}

@Suite("Pace marker")
struct PaceMarkerTests {
    @Test("A Session reset 2h away puts the marker at 60% (§12 #2)")
    func sessionTwoHoursAway() throws {
        let marker = try #require(Pace.assess(session(45, resetIn: 2 * hour), now: now).markerPercent)
        #expect(abs(marker - 60) <= 1)
    }

    @Test("A Weekly reset 3.5 days away puts the marker at 50% (§12 #3)")
    func weeklyHalfway() throws {
        let marker = try #require(Pace.assess(weekly(30, resetIn: 3.5 * day), now: now).markerPercent)
        #expect(abs(marker - 50) <= 1)
    }

    @Test("The marker is at 0% when the Window has just started")
    func windowStart() {
        #expect(Pace.markerFraction(windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(5 * hour), now: now) == 0)
    }

    @Test("The marker is at 100% at the moment of reset")
    func windowEnd() {
        let fraction = Pace.markerFraction(windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(0.000_1), now: now)
        #expect(fraction.map { abs($0 - 1) < 0.001 } == true)
    }

    @Test("A reset in the past treats the Window as reset: marker at 0% (§10, §12 #11)")
    func resetInPast() {
        #expect(Pace.markerFraction(windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(-10 * 60), now: now) == 0)
        #expect(Pace.markerFraction(windowLength: WindowLength.claudeSession, resetsAt: now, now: now) == 0)
    }

    @Test("A reset further away than the Window length clamps to 0%")
    func resetBeyondWindow() {
        #expect(Pace.markerFraction(windowLength: WindowLength.claudeSession, resetsAt: now.addingTimeInterval(6 * hour), now: now) == 0)
    }

    @Test("No reset time means no marker (P6)")
    func noResetTime() {
        let pace = Pace.assess(session(10, resetIn: nil), now: now)
        #expect(pace.markerPercent == nil)
        #expect(pace.label == nil)
    }

    @Test("No Window length means no marker and no pace colouring (P0)")
    func noWindowLength() {
        let limit = LimitUsage(name: "Credits", percentUsed: 95, windowLength: nil, resetsAt: now.addingTimeInterval(hour))
        let pace = Pace.assess(limit, now: now)
        #expect(pace.markerPercent == nil)
        #expect(pace.band == .neutral)
        #expect(pace.label == nil)
    }

    @Test("The marker moves as time passes, with the same usage figure (P5)")
    func markerMoves() throws {
        let limit = session(45, resetIn: 2 * hour)
        let first = try #require(Pace.assess(limit, now: now).markerPercent)
        let later = try #require(Pace.assess(limit, now: now.addingTimeInterval(5 * 60)).markerPercent)
        #expect(later > first)
    }
}

@Suite("Pace colouring and labels (§12 #4)")
struct PaceColouringTests {
    // Marker at 60% for every case below.
    private func assess(_ used: Double) -> PaceAssessment {
        Pace.assess(session(used, resetIn: 2 * hour), now: now)
    }

    @Test("At 0% usage the bar is green and on pace (§12 #11)")
    func zeroUsage() {
        #expect(assess(0).band == .green)
        #expect(assess(0).label == "on pace")
    }

    @Test("Usage at or below the marker is green, on pace (C1)")
    func onPace() {
        #expect(assess(45).band == .green)
        #expect(assess(45).label == "on pace")
        #expect(assess(60).band == .green)
        #expect(assess(60).label == "on pace")
    }

    @Test("Usage just over the marker is amber (C2)")
    func slightlyOver() {
        #expect(assess(61).band == .amber)
        #expect(assess(61).label == "over +1%")
        #expect(assess(68).label == "over +8%")
    }

    @Test("Usage exactly marker + 10 pp is still amber (C2)")
    func amberBoundary() {
        #expect(assess(70).band == .amber)
        #expect(assess(70).label == "over +10%")
    }

    @Test("Usage more than marker + 10 pp is red (C3)")
    func wellOver() {
        #expect(assess(70.5).band == .red)
        #expect(assess(72).band == .red)
        #expect(assess(72).label == "over +12%")
    }

    @Test("Usage at or above 90% is red even when on pace (C3)")
    func ninetyRule() {
        let limit = session(90, resetIn: 0.1 * hour) // marker at 98%
        let pace = Pace.assess(limit, now: now)
        #expect(pace.band == .red)
        #expect(pace.label == "on pace")
        #expect(Pace.band(used: 89.9, marker: 98) == .green)
    }

    @Test("Usage at 100% is red (§12 #11)")
    func fullUsage() {
        #expect(assess(100).band == .red)
        #expect(Pace.band(used: 100, marker: 100) == .red)
    }

    @Test("Over pace never reads over +0%")
    func tinyOverage() {
        #expect(Pace.label(used: 60.2, marker: 60) == "over +1%")
    }

    @Test("The threshold is one constant (C4)")
    func thresholdConstant() {
        #expect(Pace.overPaceThreshold == 10)
        #expect(Pace.band(used: 60 + Pace.overPaceThreshold, marker: 60) == .amber)
        #expect(Pace.band(used: 60 + Pace.overPaceThreshold + 0.01, marker: 60) == .red)
    }

    @Test("A missing usage figure is neutral, not 0% (R6)")
    func missingUsage() {
        let missing = Pace.assess(session(nil, resetIn: 2 * hour), now: now)
        #expect(missing.band == .neutral)
        #expect(missing.label == nil)
    }
}
