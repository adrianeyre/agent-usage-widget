import AgentUsageCore
import SwiftUI

// Agent Usage's design system: one set of spacing, radii, type and colour roles, and
// the small parts every surface shares (the widgets, the menu-bar dropdown and the
// Manage Accounts window). Everything uses SF Pro, SF Symbols and the system's
// semantic colours, so light mode, dark mode, Increase Contrast and the accent
// colour all follow the Owner's settings. See docs/guide/design.md.

/// The 4-point spacing scale.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
}

/// Corner radii, all drawn `.continuous`.
public enum Radius {
    public static let badge: CGFloat = 6
    public static let control: CGFloat = 8
    public static let card: CGFloat = 12
    /// The system's widget corner, for previews that stand in for a widget.
    public static let widget: CGFloat = 20
}

/// Type roles. Figures are rounded and monospaced so they don't jitter as they change.
public enum Typeface {
    public static let figureLarge = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    public static let figure = Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
    public static let figureSmall = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
}

// MARK: - Colour roles

extension PaceBand {
    /// The bar's fill (C1–C3). Never the only signal: `PaceLabel` says it in words too (C5).
    public var color: Color {
        switch self {
        case .green: .green
        case .amber: .orange
        case .red: .red
        case .neutral: .accentColor
        }
    }

    /// The symbol shown beside the pace text, so the band reads without colour.
    public var symbol: String {
        switch self {
        case .green: "checkmark.circle.fill"
        case .amber: "arrow.up.right.circle.fill"
        case .red: "exclamationmark.circle.fill"
        case .neutral: "circle.dashed"
        }
    }
}

extension AccountStatus {
    /// Orange rather than yellow for Stale: yellow text fails 4.5:1 on a light background.
    public var color: Color {
        switch self {
        case .ok: .green
        case .stale: .orange
        case .signInRequired: .red
        case .reauthoriseBy: .orange
        }
    }

    public var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .signInRequired: "person.crop.circle.badge.exclamationmark"
        case .reauthoriseBy: "key.fill"
        }
    }

    /// Whether the Owner needs to act, which makes Re-authorise the prominent button.
    public var needsAttention: Bool {
        switch self {
        case .ok, .stale: false
        case .signInRequired, .reauthoriseBy: true
        }
    }
}

// MARK: - Parts

/// A Provider's neutral glyph on a quiet tile (PV4: text and a glyph, never a logo).
public struct ProviderBadge: View {
    let glyph: String
    let name: String
    var size: CGFloat

    public init(glyph: String, name: String, size: CGFloat = 24) {
        self.glyph = glyph
        self.name = name
        self.size = size
    }

    public var body: some View {
        Image(systemName: glyph)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityLabel(name)
    }
}

/// An Account's status as a small capsule: symbol, words and colour together.
public struct StatusChip: View {
    let status: AccountStatus

    public init(status: AccountStatus) {
        self.status = status
    }

    public var body: some View {
        Label(UsageFormatting.statusText(status), systemImage: status.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(status.color)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(status.color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// `on pace` / `over +8%` with its band's symbol, or the Limit's state when it has no pace.
public struct PaceLabel: View {
    let limit: LimitDisplay
    /// Show the state text (`Limit reached`, `No active session`) when there's no pace.
    var showsState: Bool

    public init(limit: LimitDisplay, showsState: Bool = true) {
        self.limit = limit
        self.showsState = showsState
    }

    public var body: some View {
        if let pace = limit.paceLabel {
            Label {
                Text(pace)
            } icon: {
                Image(systemName: limit.band.symbol).foregroundStyle(limit.band.color)
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.secondary)
        } else if showsState, let state = limit.compactText {
            Text(state)
                .foregroundStyle(limit.isLimitReached ? Color.red : Color.secondary)
        }
    }
}

/// A label whose icon sits close to its text, for tight rows.
public struct CompactLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xxs + 1) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// The number of the widget that shows an Account (§6.1, ADR-0009).
public struct WidgetNumberBadge: View {
    let number: Int?

    public init(number: Int?) {
        self.number = number
    }

    public var body: some View {
        Text(number.map(String.init) ?? "–")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(number == nil ? .tertiary : .secondary)
            .frame(minWidth: 18, minHeight: 18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(number.map { "Widget \($0)" } ?? "No widget")
    }
}
