import AgentUsageCore
import SwiftUI

public enum WidgetSize: Sendable {
    case small
    case medium
}

/// The whole widget for one Account, in either size. Takes display content worked out by
/// the core from a Snapshot and a `Date`, and does no I/O.
public struct AccountWidgetView: View {
    let content: WidgetContent
    let size: WidgetSize
    /// The widget's number, shown when its slot is empty.
    let slot: Int

    public init(content: WidgetContent, size: WidgetSize, slot: Int = 1) {
        self.content = content
        self.size = size
        self.slot = slot
    }

    /// Convenience for callers holding the published Account and the timeline date.
    public init(account: PublishedAccount?, now: Date, size: WidgetSize, slot: Int = 1) {
        self.init(content: DisplayModel.content(for: account, now: now), size: size, slot: slot)
    }

    public var body: some View {
        switch content {
        case .chooseAccount:
            ChooseAccountView(size: size, slot: slot)
        case .account(let card):
            switch size {
            case .medium: MediumAccountView(card: card)
            case .small: SmallAccountView(card: card)
            }
        }
    }
}

// MARK: - Medium

/// About 340 × 160 pt (§6.1): the Account's header, then up to two Limits, each with its
/// figure, reset time, bar and pace.
public struct MediumAccountView: View {
    let card: AccountCard

    public init(card: AccountCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            if card.signInRequired {
                MessageView(symbol: "person.crop.circle.badge.exclamationmark", tint: .red, title: "Sign in required", hint: "Click to open Agent Usage and Re-authorise.")
            } else if card.awaitingFirstFetch {
                MessageView(symbol: "clock", tint: .secondary, title: "Waiting for the first update", hint: "Agent Usage fetches every 5 minutes.")
            } else {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(card.limits) { limit in
                        MediumLimitRow(limit: limit)
                    }
                }
                .opacity(card.isStale ? 0.45 : 1)
            }
            Spacer(minLength: 0)
            if let reauthorise = card.reauthoriseText {
                Label(reauthorise, systemImage: "key.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            ProviderBadge(glyph: card.providerGlyph, name: card.providerName, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.accountName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                // The email is cut short in the middle when it's too long (§6.1).
                Text("\(card.providerName) · \(card.emailVerified ? card.email : "\(card.email) (unverified)")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.xs)
            UpdatedBadge(text: card.updatedText, isStale: card.isStale)
        }
    }
}

struct MediumLimitRow: View {
    let limit: LimitDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(limit.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(limit.percentText)
                    .font(Typeface.figure)
                    .foregroundStyle(limit.isLimitReached ? Color.red : Color.primary)
                    .contentTransition(.numericText())
                Spacer(minLength: Spacing.xs)
                if let detail = limit.detailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(limit.isLimitReached ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: Spacing.m) {
                UsageBarView(limit: limit)
                // A fixed width keeps both bars the same length, so their markers compare.
                PaceLabel(limit: limit, showsState: false)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
            }
        }
    }
}

// MARK: - Small

/// The Provider glyph, the Account name and up to two bars, with no email and no reset
/// text (§6.1).
public struct SmallAccountView: View {
    let card: AccountCard

    public init(card: AccountCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ProviderBadge(glyph: card.providerGlyph, name: card.providerName, size: 20)
                Text(card.accountName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if card.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Stale")
                }
            }
            if card.signInRequired {
                MessageView(symbol: "person.crop.circle.badge.exclamationmark", tint: .red, title: "Sign in required", hint: nil)
            } else if card.awaitingFirstFetch {
                MessageView(symbol: "clock", tint: .secondary, title: "Waiting for update", hint: nil)
            } else {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(card.limits) { limit in
                        SmallLimitRow(limit: limit)
                    }
                }
                .opacity(card.isStale ? 0.45 : 1)
            }
            Spacer(minLength: 0)
            if let reauthorise = card.reauthoriseText {
                Text(reauthorise)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

struct SmallLimitRow: View {
    let limit: LimitDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(limit.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xxs)
                Text(limit.percentText)
                    .font(Typeface.figureSmall)
                    .foregroundStyle(limit.isLimitReached ? Color.red : Color.primary)
            }
            UsageBarView(limit: limit, barHeight: 8)
            PaceLabel(limit: limit)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

// MARK: - Shared

/// `Updated 2m ago`, with a warning symbol when the figures are Stale (R3, R4).
struct UpdatedBadge: View {
    let text: String
    let isStale: Bool

    var body: some View {
        HStack(spacing: Spacing.xxs + 1) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Stale")
            }
            Text(text)
                .foregroundStyle(isStale ? Color.orange : Color.secondary)
        }
        .font(.caption2.weight(isStale ? .semibold : .regular))
        .lineLimit(1)
        .fixedSize()
    }
}

/// A widget whose number has no Account (§6.1, ADR-0009).
struct ChooseAccountView: View {
    let size: WidgetSize
    let slot: Int

    var body: some View {
        VStack(spacing: Spacing.s) {
            Text("\(slot)")
                .font(Typeface.figure)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                .accessibilityHidden(true)
            Text("No Account \(slot)")
                .font(.subheadline.weight(.semibold))
            Text(size == .medium
                 ? "This widget shows Account \(slot) in Manage Accounts. Add an Account, or move one up or down to number \(slot)."
                 : "Add or move an Account to number \(slot) in Manage Accounts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A state with no figures: Sign in required, or waiting for the first fetch.
struct MessageView: View {
    let symbol: String
    let tint: Color
    let title: String
    let hint: String?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.callout.weight(.semibold))
                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.xs)
    }
}
