import Foundation

/// Tolerant readers for Provider JSON: a missing or odd value becomes `nil`, never a crash (§7.3).
enum JSONValue {
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    static func date(_ value: Any?) -> Date? {
        switch value {
        case let string as String:
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) { return date }
            return ISO8601DateFormatter().date(from: string)
        case let number as NSNumber:
            // Seconds, or milliseconds when the value is too large to be seconds.
            let value = number.doubleValue
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        default:
            return nil
        }
    }
}

/// The version and build number shown in About (B5).
public enum AppInfo {
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
