import AgentUsageCore
import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// **Open at login** through `SMAppService`: on by default, with a switch to turn it off (§8).
@MainActor
@Observable
public final class LoginItemController {
    static let configuredKey = "OpenAtLoginConfigured"
    public private(set) var isEnabled = false
    public private(set) var lastError: String?
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    /// Registers the app the first time it runs, so Open at login starts on.
    public func applyDefault() {
        guard !defaults.bool(forKey: Self.configuredKey) else { return }
        defaults.set(true, forKey: Self.configuredKey)
        setEnabled(true)
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    public func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// Owns the model and the Manage Accounts window, and handles `agentusage://` links from
/// widgets (U5).
@MainActor
@Observable
public final class AppController {
    public let model: AppModel
    public let loginItem: LoginItemController
    /// The Account selected in Manage Accounts.
    public var selectedAccountID: UUID?
    /// When set, Manage Accounts opens the Re-authorise sheet for this Account.
    public var reauthoriseAccountID: UUID?
    /// When set, Manage Accounts opens the Add Account sheet.
    public var addingAccount = false

    @ObservationIgnored private var window: NSWindow?

    public init(model: AppModel, loginItem: LoginItemController) {
        self.model = model
        self.loginItem = loginItem
    }

    public func start() {
        loginItem.applyDefault()
        model.startRefreshing()
    }

    public func showManageAccounts(selecting id: UUID? = nil, adding: Bool = false) {
        if let id { selectedAccountID = id }
        if adding { addingAccount = true }
        if window == nil {
            let hosting = NSHostingController(rootView: ManageAccountsView(controller: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Manage Accounts"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    public func reauthorise(_ id: UUID) {
        reauthoriseAccountID = id
        showManageAccounts(selecting: id)
    }

    /// `agentusage://account/<id>` opens Manage Accounts with that Account selected (U5).
    public func handle(_ url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        if let id = DeepLink.accountID(from: url), model.account(id) != nil {
            showManageAccounts(selecting: id)
        } else {
            showManageAccounts()
        }
    }
}
