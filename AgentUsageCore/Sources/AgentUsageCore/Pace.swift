import Foundation

/// The fill colour band for a bar (C1–C3). `neutral` is for a Limit with no Window
/// length (P0) or no usage figure.
public enum PaceBand: String, Codable, Hashable, Sendable {
    case green
    case amber
    case red
    case neutral
}

/// Where a Limit stands against its Pace marker at a given moment.
public struct PaceAssessment: Hashable, Sendable {
    /// The Pace marker position, 0–100. `nil` when there's no marker (P0, P6).
    public var markerPercent: Double?
    public var band: PaceBand
    /// `on pace` / `over +12%` (C5). `nil` when there's no marker.
    public var label: String?

    public init(markerPercent: Double?, band: PaceBand, label: String?) {
        self.markerPercent = markerPercent
        self.band = band
        self.label = label
    }
}

/// Pace maths. Everything is a pure function of the Limit and `now`, so the marker
/// moves on every timeline entry without a new fetch (P5, R2).
public enum Pace {
    /// How many percentage points over the marker still counts as amber (C2, C4).
    public static let overPaceThreshold: Double = 10
    /// Usage at or above this is always red (C3).
    public static let redUsageThreshold: Double = 90
    /// Usage at or above this means the Limit has been reached (§10).
    public static let limitReachedThreshold: Double = 100

    /// The expected-usage position as a fraction 0–1 of the bar (P1–P4).
    ///
    /// - Returns `nil` with no Window length (P0) or no reset time (P6).
    /// - Returns 0 when the reset time is in the past: the Window is treated as reset (§10).
    public static func markerFraction(windowLength: TimeInterval?, resetsAt: Date?, now: Date) -> Double? {
        guard let windowLength, windowLength > 0, let resetsAt else { return nil }
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0 else { return 0 }
        let elapsed = windowLength - timeUntilReset
        return min(max(elapsed / windowLength, 0), 1)
    }

    public static func assess(_ limit: LimitUsage, now: Date) -> PaceAssessment {
        let marker = markerFraction(windowLength: limit.windowLength, resetsAt: limit.resetsAt, now: now)
            .map { $0 * 100 }

        guard let used = limit.percentUsed else {
            return PaceAssessment(markerPercent: marker, band: .neutral, label: nil)
        }
        guard let marker else {
            // No marker means no pace colouring (P0), but a reached Limit is still red (§10).
            let band: PaceBand = used >= limitReachedThreshold ? .red : .neutral
            return PaceAssessment(markerPercent: nil, band: band, label: nil)
        }
        return PaceAssessment(markerPercent: marker, band: band(used: used, marker: marker), label: label(used: used, marker: marker))
    }

    /// C1–C3.
    public static func band(used: Double, marker: Double) -> PaceBand {
        if used >= redUsageThreshold || used > marker + overPaceThreshold { return .red }
        if used > marker { return .amber }
        return .green
    }

    /// C5. Over pace is never shown as `over +0%`.
    public static func label(used: Double, marker: Double) -> String {
        guard used > marker else { return "on pace" }
        let over = max(1, Int((used - marker).rounded()))
        return "over +\(over)%"
    }
}
