import AgentUsageCore
import AgentUsageViews
import AppKit
import SwiftUI

/// The menu-bar dropdown (§6.2): a header with when everything was last updated, a card
/// per Account in Manage Accounts order, then Refresh now, Manage Accounts… and Quit.
public struct MenuContentView: View {
    let controller: AppController
    /// More Accounts than this scroll, so the dropdown never runs off the screen.
    static let visibleAccounts = 4

    public init(controller: AppController) {
        self.controller = controller
    }

    private var model: AppModel { controller.model }

    public var body: some View {
        // Ticks so `stale` and `Updated …` stay right while the dropdown is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                MenuHeader(
                    lastRefresh: model.lastRefresh,
                    isRefreshing: model.accounts.contains { model.runtime[$0.id]?.isFetching ?? false },
                    count: model.accounts.count,
                    now: context.date
                )
                Divider()
                if model.accounts.isEmpty {
                    MenuEmptyState { controller.showManageAccounts(adding: true) }
                } else if model.accounts.count > Self.visibleAccounts {
                    ScrollView { cards(now: context.date) }
                        .frame(height: 452)
                } else {
                    cards(now: context.date)
                }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    MenuActionRow(title: "Refresh now", symbol: "arrow.clockwise", shortcut: "R") { model.refreshNow() }
                        .disabled(model.accounts.isEmpty)
                    MenuActionRow(title: "Manage Accounts…", symbol: "person.2", shortcut: ",") { controller.showManageAccounts() }
                    Divider().padding(.vertical, Spacing.xs).padding(.horizontal, Spacing.m)
                    MenuActionRow(title: "Quit Agent Usage", symbol: "power", shortcut: "Q") { NSApp.terminate(nil) }
                }
                .padding(Spacing.s)
            }
            .frame(width: 360)
        }
    }

    private func cards(now: Date) -> some View {
        VStack(spacing: Spacing.xs) {
            ForEach(model.accounts) { account in
                AccountMenuCard(
                    card: model.card(for: account, now: now),
                    isFetching: model.runtime[account.id]?.isFetching ?? false,
                    onOpen: { controller.showManageAccounts(selecting: account.id) },
                    onReauthorise: { controller.reauthorise(account.id) }
                )
            }
        }
        .padding(Spacing.s)
    }
}

/// The app's name, how many Accounts it tracks and when it last fetched.
struct MenuHeader: View {
    let lastRefresh: Date?
    let isRefreshing: Bool
    let count: Int
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Agent Usage").font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m + 2)
    }

    private var subtitle: String {
        if isRefreshing { return "Refreshing…" }
        let accounts = count == 1 ? "1 Account" : "\(count) Accounts"
        guard count > 0 else { return "No Accounts yet" }
        guard let lastRefresh else { return accounts }
        return "\(accounts) · \(UsageFormatting.updatedText(fetchedAt: lastRefresh, now: now))"
    }
}

/// No Accounts: what to do next, with the button that does it.
struct MenuEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Accounts yet").font(.headline)
            Text("Add a Claude, Codex or Copilot Account to see its usage here and in a widget.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Account…", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// One Account (§6.2): Provider, name, email, each Limit's % used with its bar, the status
/// and a Re-authorise button. Clicking the card opens it in Manage Accounts.
struct AccountMenuCard: View {
    let card: AccountCard
    let isFetching: Bool
    let onOpen: () -> Void
    let onReauthorise: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.m) {
                ProviderBadge(glyph: card.providerGlyph, name: card.providerName, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.accountName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("\(card.providerName) · \(card.email)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .layoutPriority(1)
                Spacer(minLength: Spacing.xs)
                if isFetching {
                    ProgressView().controlSize(.mini).accessibilityLabel("Refreshing")
                }
                StatusChip(status: card.status)
                if !card.status.needsAttention {
                    Button(action: onReauthorise) {
                        Image(systemName: "key")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Re-authorise \(card.accountName)")
                    .accessibilityLabel("Re-authorise \(card.accountName)")
                }
            }

            if card.signInRequired {
                Text("Agent Usage can't read this Account's usage until it's signed in again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if card.awaitingFirstFetch {
                Text("Waiting for the first update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Spacing.s) {
                    ForEach(card.limits) { limit in
                        MenuLimitRow(limit: limit)
                    }
                }
                .opacity(card.isStale ? 0.5 : 1)
            }

            if card.isStale {
                Label(card.updatedText, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if card.status.needsAttention {
                Button(action: onReauthorise) {
                    Label("Re-authorise", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(card.status.color)
                .controlSize(.regular)
            }
        }
        .padding(Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open in Manage Accounts", onOpen)
    }
}

/// A Limit in a menu card on one line: name, bar, then the band's symbol and % used, so
/// the pace reads without colour. The pace in words is the bar's accessibility value.
struct MenuLimitRow: View {
    let limit: LimitDisplay

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(limit.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            UsageBarView(limit: limit, barHeight: 6)
            HStack(spacing: Spacing.xxs + 1) {
                Image(systemName: limit.isLimitReached ? PaceBand.red.symbol : limit.band.symbol)
                    .font(.caption2)
                    .foregroundStyle(limit.isLimitReached ? Color.red : limit.band.color)
                    .accessibilityHidden(true)
                Text(limit.percentText)
                    .font(Typeface.figureSmall)
                    .foregroundStyle(limit.isLimitReached ? Color.red : Color.primary)
            }
            .frame(width: 52, alignment: .trailing)
        }
        .help([limit.paceLabel, limit.detailText].compactMap { $0 }.joined(separator: " · "))
    }
}

/// A menu item: symbol, title and its shortcut, highlighted like a native menu on hover.
struct MenuActionRow: View {
    let title: String
    let symbol: String
    let shortcut: KeyEquivalent
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(title)
                Spacer()
                Text("⌘\(String(shortcut.character).uppercased())")
                    .font(.callout.monospaced())
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
            }
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var highlighted: Bool { hovering && isEnabled }
}
