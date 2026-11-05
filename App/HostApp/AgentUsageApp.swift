import AgentUsageHostKit
import AppKit
import SwiftUI

/// The menu-bar host app (ADR-0002): no Dock icon, a plain glyph with no numbers (§6.2).
@main
struct AgentUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Agent Usage", systemImage: "gauge.with.dots.needle.33percent") {
            MenuContentView(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController(model: .live(), loginItem: LoginItemController())

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    /// `agentusage://account/<id>` from a widget (U5).
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(controller.handle)
    }
}
