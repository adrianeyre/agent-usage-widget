import Foundation

/// Text shown on the widgets and menu rows. Every function takes `now` and a calendar,
/// so tests are deterministic.
public enum UsageFormatting {
    /// `42%` (F3). `—` when the figure is missing, never a made-up number (R6).
    public static func percentText(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        return "\(Int(percent.rounded()))%"
    }

    /// `resets in 2h 14m` within a day, otherwise `resets Mon 09:00` (F4).
    public static func resetText(resetsAt: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return "resets now" }
        if remaining < 24 * 60 * 60 {
            return "resets in \(duration(remaining))"
        }
        return "resets \(weekdayTime(resetsAt, calendar: calendar))"
    }

    /// `2h 14m`, `14m`, `<1m`. Minutes are rounded up so a reset never shows as `0m`.
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return String(format: "%dh %02dm", hours, rest)
    }

    /// `Updated 3m ago` (R3).
    public static func updatedText(fetchedAt: Date?, now: Date) -> String {
        guard let fetchedAt else { return "Not updated yet" }
        let elapsed = max(0, now.timeIntervalSince(fetchedAt))
        let minutes = Int(elapsed / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours)h ago" }
        return "Updated \(hours / 24)d ago"
    }

    /// `Re-authorise by 12 Nov` (U3).
    public static func reauthoriseText(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "Re-authorise by \(formatter.string(from: date))"
    }

    static func weekdayTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }

    public static func statusText(_ status: AccountStatus, calendar: Calendar = .current) -> String {
        switch status {
        case .ok: "ok"
        case .stale: "stale"
        case .signInRequired: "Sign in required"
        case .reauthoriseBy(let date): reauthoriseText(date, calendar: calendar)
        }
    }
}
