// Renders the app's real SwiftUI views with sample Accounts and writes them as PNGs,
// for the README, docs/guide/screenshots.md and the website (which copies docs/images/).
//
//     scripts/screenshots.sh            # writes docs/images/*.png
//
// Every figure here is sample data. Nothing is read from or written to the Owner's
// Accounts: the model keeps its Accounts in memory and its published files in a
// temporary folder, and no Provider is ever called.
import AgentUsageCore
@testable import AgentUsageHostKit
import AgentUsageViews
import AppKit
import SwiftUI

// MARK: - Sample data

/// Returns canned Limits for each sample Account, as if just fetched.
final class SampleProvider: UsageProvider, @unchecked Sendable {
    let limits: [UUID: [LimitUsage]]
    let fetchedAgo: TimeInterval

    init(limits: [UUID: [LimitUsage]], fetchedAgo: TimeInterval = 2 * 60) {
        self.limits = limits
        self.fetchedAgo = fetchedAgo
    }

    func fetch(for account: Account) async throws -> UsageSnapshot {
        UsageSnapshot(accountID: account.id, limits: limits[account.id] ?? [], fetchedAt: Date().addingTimeInterval(-fetchedAgo))
    }
}

final class SampleAccountStore: AccountStore, @unchecked Sendable {
    var accounts: [Account] = []
    func load() -> [Account] { accounts }
    func save(_ accounts: [Account]) throws { self.accounts = accounts }
}

enum Sample {
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 24 * hour

    static let work = Account(provider: .claude, name: "Work", email: "ada@example-company.com", emailVerified: true, organisationName: "Example Company")
    static let personal = Account(provider: .claude, name: "Personal", email: "ada.lovelace@example.com", emailVerified: true)
    static let codex = Account(provider: .codex, name: "ChatGPT", email: "ada.lovelace@example.com", emailVerified: true, organisationID: "codex:ChatGPT Plus", organisationName: "ChatGPT Plus")
    static let copilot = Account(provider: .copilot, name: "Copilot", email: "@ada-lovelace", emailVerified: true, enteredAuthorisationExpiry: Date().addingTimeInterval(5 * day))

    static func limits(now: Date) -> [UUID: [LimitUsage]] {
        func at(_ interval: TimeInterval) -> Date { now.addingTimeInterval(interval) }
        return [
            work.id: [
                LimitUsage(name: "Session (5h)", percentUsed: 45, windowLength: WindowLength.claudeSession, resetsAt: at(2 * hour)),
                LimitUsage(name: "Weekly", percentUsed: 38, windowLength: WindowLength.claudeWeekly, resetsAt: at(3.5 * day)),
            ],
            personal.id: [
                LimitUsage(name: "Session (5h)", percentUsed: 72, windowLength: WindowLength.claudeSession, resetsAt: at(2.4 * hour)),
                LimitUsage(name: "Weekly", percentUsed: 61, windowLength: WindowLength.claudeWeekly, resetsAt: at(3.1 * day)),
            ],
            codex.id: [
                LimitUsage(name: "5h", percentUsed: 18, windowLength: 5 * hour, resetsAt: at(3.6 * hour)),
                LimitUsage(name: "Weekly", percentUsed: 52, windowLength: WindowLength.claudeWeekly, resetsAt: at(3.2 * day)),
            ],
            copilot.id: [
                LimitUsage(name: "Chat", percentUsed: 24, windowLength: 30 * day, resetsAt: at(19 * day)),
                LimitUsage(name: "Completions", percentUsed: 9, windowLength: 30 * day, resetsAt: at(19 * day)),
            ],
        ]
    }

    @MainActor
    static func controller(accounts: [Account] = [work, personal, codex, copilot]) async -> AppController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-usage-screenshots-\(UUID().uuidString)")
        let provider = SampleProvider(limits: limits(now: Date()))
        let model = AppModel(
            accountStore: SampleAccountStore(),
            authorisations: InMemoryAuthorisationStore(),
            publishedStore: PublishedStore(root: root),
            providers: ProviderRegistry(providers: [.claude: provider, .codex: provider, .copilot: provider]),
            defaults: UserDefaults(suiteName: "agent-usage-screenshots-\(UUID().uuidString)")!,
            reloadWidgets: {}
        )
        for account in accounts {
            _ = try? model.add(account, authorisation: account.provider == .copilot ? "github_pat_" + String(repeating: "x", count: 40) : nil)
        }
        await model.refreshAll()
        let controller = AppController(model: model, loginItem: LoginItemController(defaults: UserDefaults(suiteName: "agent-usage-screenshots")!))
        controller.selectedAccountID = accounts.first?.id
        return controller
    }

    static func published(_ state: PreviewData.State) -> PublishedAccount? {
        PreviewData.account(state)
    }
}

// MARK: - Rendering

@MainActor
enum Renderer {
    static let scale: CGFloat = 2
    static var output = URL(fileURLWithPath: "docs/images", isDirectory: true)

    /// Lays a view out in an off-screen window in the given appearance and writes it at 2x.
    static func write<V: View>(_ name: String, dark: Bool = false, size: CGSize? = nil, @ViewBuilder _ view: () -> V) async throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let root = view()
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let fitting = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: fitting)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        // Let SwiftUI lay out, load symbols and settle its first animations.
        try await Task.sleep(for: .milliseconds(700))
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)

        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let url = output.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("wrote \(url.path) (\(Int(bounds.width))×\(Int(bounds.height)) pt)")
    }
}

// MARK: - Scenes

/// A soft desktop behind the widgets, so they read as widgets rather than cards.
struct Desktop<Content: View>: View {
    let dark: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(28)
            .background(
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.10, green: 0.13, blue: 0.20), Color(red: 0.16, green: 0.12, blue: 0.24)]
                        : [Color(red: 0.80, green: 0.87, blue: 0.96), Color(red: 0.91, green: 0.86, blue: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
    }
}

/// One widget at its desktop size, on the system's widget material.
struct WidgetTile: View {
    let account: PublishedAccount?
    let size: WidgetSize
    var slot = 1

    var body: some View {
        AccountWidgetView(account: account, now: Date(), size: size, slot: slot)
            .padding(16)
            .frame(width: size == .medium ? 344 : 160, height: 160)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.widget, style: .continuous))
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.widget, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

/// The menu-bar dropdown on a window-coloured panel, as macOS draws it.
struct MenuPanel: View {
    let controller: AppController

    var body: some View {
        MenuContentView(controller: controller)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .padding(24)
    }
}

/// A window with its title bar, around a view that would sit in it.
struct WindowFrame<Content: View>: View {
    let title: String
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            content()
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .padding(24)
    }
}

@MainActor
func renderAll() async throws {
    for dark in [false, true] {
        let suffix = dark ? "-dark" : ""

        try await Renderer.write("widgets\(suffix)", dark: dark) {
            Desktop(dark: dark) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        WidgetTile(account: Sample.published(.onPace), size: .medium)
                        WidgetTile(account: Sample.published(.overPace), size: .small)
                    }
                    HStack(spacing: 20) {
                        WidgetTile(account: Sample.published(.limitReached), size: .small)
                        WidgetTile(account: Sample.published(.overPace), size: .medium)
                    }
                }
            }
        }

        let controller = await Sample.controller()
        try await Renderer.write("menu\(suffix)", dark: dark) {
            MenuPanel(controller: controller)
        }
        try await Renderer.write("manage-accounts\(suffix)", dark: dark) {
            WindowFrame(title: "Manage Accounts", size: CGSize(width: 780, height: 720)) {
                ManageAccountsView(controller: controller)
            }
        }
    }

    // Every widget state, light and dark (§12 #10).
    let states: [PreviewData.State] = [.onPace, .overPace, .limitReached, .stale, .reauthoriseBy, .signInRequired, .noActiveSession, .chooseAccount]
    for dark in [false, true] {
        try await Renderer.write("widget-states\(dark ? "-dark" : "")", dark: dark) {
            Desktop(dark: dark) {
                Grid(horizontalSpacing: 20, verticalSpacing: 14) {
                    ForEach(Array(stride(from: 0, to: states.count, by: 2)), id: \.self) { index in
                        GridRow {
                            ForEach(states[index..<min(index + 2, states.count)], id: \.self) { state in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(state.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 14) {
                                        WidgetTile(account: Sample.published(state), size: .medium, slot: 3)
                                        WidgetTile(account: Sample.published(state), size: .small, slot: 3)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Add Account, at its first step.
    let controller = await Sample.controller()
    try await Renderer.write("add-account") {
        AddAccountSheet(model: controller.model) { _ in }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .padding(24)
    }

    // No Accounts yet.
    let empty = await Sample.controller(accounts: [])
    try await Renderer.write("menu-empty") {
        MenuPanel(controller: empty)
    }
}

let folder = CommandLine.arguments.dropFirst().first

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    if let folder { Renderer.output = URL(fileURLWithPath: folder, isDirectory: true) }
    do {
        try await renderAll()
        // Exit without closing the windows, so no view's onDisappear runs.
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("screenshots: \(error)\n".utf8))
        exit(1)
    }
}
app.run()
