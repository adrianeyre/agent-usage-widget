import AgentUsageCore
import AgentUsageViews
import SwiftUI
import WidgetKit

// MARK: - Numbered slots (§6.1, ADR-0009)
//
// Each widget shows the Account at its number in Manage Accounts: "Account 1" shows the
// first, and so on. Moving an Account up or down changes which widget shows it.
//
// There's no Edit Widget picker. A configurable widget needs App Intents, and macOS's App
// Intents service refuses an extension with no Team ID ("Unable to get teamId"), which a
// self-signed build never has (ADR-0004, #17).

protocol WidgetSlot {
    static var number: Int { get }
}

enum Slot1: WidgetSlot { static let number = 1 }
enum Slot2: WidgetSlot { static let number = 2 }
enum Slot3: WidgetSlot { static let number = 3 }
enum Slot4: WidgetSlot { static let number = 4 }
enum Slot5: WidgetSlot { static let number = 5 }
enum Slot6: WidgetSlot { static let number = 6 }

// MARK: - Timeline

struct AccountEntry: TimelineEntry {
    let date: Date
    /// `nil` shows `No Account <n>`: fewer Accounts than this widget's number.
    let account: PublishedAccount?
}

/// Only reads the host app's published files. It never makes network calls or touches
/// Authorisations (ADR-0002). Entries every 5 minutes move the marker between fetches (P5, R2).
struct AccountTimelineProvider<Slot: WidgetSlot>: TimelineProvider {
    static var entrySpacing: TimeInterval { 5 * 60 }
    static var entryCount: Int { 12 }

    func placeholder(in context: Context) -> AccountEntry {
        AccountEntry(date: Date(), account: PreviewData.account(.onPace))
    }

    func getSnapshot(in context: Context, completion: @escaping (AccountEntry) -> Void) {
        let account = PublishedStore().account(atSlot: Slot.number)
        // The widget gallery shows sample bars until an Account exists for this slot.
        if account == nil, context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(AccountEntry(date: Date(), account: account))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AccountEntry>) -> Void) {
        let account = PublishedStore().account(atSlot: Slot.number)
        let now = Date()
        let entries = (0..<Self.entryCount).map { index in
            AccountEntry(date: now.addingTimeInterval(Double(index) * Self.entrySpacing), account: account)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct AccountUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountEntry
    let slot: Int

    var body: some View {
        AccountWidgetView(account: entry.account, now: entry.date, size: family == .systemSmall ? .small : .medium, slot: slot)
            .containerBackground(.fill.tertiary, for: .widget)
            // Tapping opens the host app with this Account selected (U5).
            .widgetURL(entry.account.map { DeepLink.account($0.id) })
    }
}

struct AccountSlotWidget<Slot: WidgetSlot>: Widget {
    static var displayName: String { "Agent Usage: Account " + String(Slot.number) }
    static var summary: String { "Account " + String(Slot.number) + " in Manage Accounts, with a Pace marker on each bar." }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AccountSlot\(Slot.number)", provider: AccountTimelineProvider<Slot>()) { entry in
            AccountUsageWidgetView(entry: entry, slot: Slot.number)
        }
        // Plain Strings: WidgetKit crashes on an interpolated (formatted) LocalizedStringKey here.
        .configurationDisplayName(Self.displayName)
        .description(Self.summary)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AgentUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        AccountSlotWidget<Slot1>()
        AccountSlotWidget<Slot2>()
        AccountSlotWidget<Slot3>()
        AccountSlotWidget<Slot4>()
        AccountSlotWidget<Slot5>()
        AccountSlotWidget<Slot6>()
    }
}
