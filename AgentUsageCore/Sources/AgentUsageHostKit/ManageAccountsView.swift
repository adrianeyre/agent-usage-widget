import AgentUsageCore
import AgentUsageViews
import SwiftUI

/// Manage Accounts (A4, §6.2): add, rename, re-order and remove Accounts, plus the
/// Open at login switch and the About section.
public struct ManageAccountsView: View {
    @Bindable var controller: AppController
    @State private var removing: Account?
    @State private var error: String?

    public init(controller: AppController) {
        self.controller = controller
    }

    private var model: AppModel { controller.model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 250)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $controller.addingAccount) {
            AddAccountSheet(model: model) { added in
                controller.selectedAccountID = added
            }
        }
        .sheet(item: reauthoriseBinding) { account in
            ReauthoriseSheet(model: model, account: account)
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { account in
            Button("Remove", role: .destructive) {
                do {
                    try model.remove(account.id)
                    controller.selectedAccountID = model.accounts.first?.id
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } message: { account in
            Text("This deletes Agent Usage's copy of its Authorisation and its Snapshot. Your own \(account.provider.displayName) login isn't touched.")
        }
        .alert("Couldn't change Accounts", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var reauthoriseBinding: Binding<Account?> {
        Binding(
            get: { controller.reauthoriseAccountID.flatMap(model.account) },
            set: { controller.reauthoriseAccountID = $0?.id }
        )
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Selection is drawn by the row itself rather than by List, so it looks the same
            // in the app and in the screenshots; arrow keys still move it.
            List {
                Section {
                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) { position, account in
                        AccountSidebarRow(
                            account: account,
                            status: model.card(for: account).status,
                            widgetNumber: position < WidgetSlots.count ? position + 1 : nil,
                            isSelected: controller.selectedAccountID == account.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { controller.selectedAccountID = account.id }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(controller.selectedAccountID == account.id ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                                .padding(.horizontal, Spacing.s)
                        )
                        .accessibilityAddTraits(controller.selectedAccountID == account.id ? .isSelected : [])
                        .accessibilityAction { controller.selectedAccountID = account.id }
                        .contextMenu {
                            Button("Move Up") { move(account.id, .up) }.disabled(!model.canMove(account.id, .up))
                            Button("Move Down") { move(account.id, .down) }.disabled(!model.canMove(account.id, .down))
                            Divider()
                            Button("Re-authorise…") { controller.reauthoriseAccountID = account.id }
                            Button("Remove…", role: .destructive) { removing = account }
                        }
                    }
                    .onMove { source, destination in
                        do { try model.move(fromOffsets: source, toOffset: destination) } catch { self.error = error.localizedDescription }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    if !model.accounts.isEmpty {
                        Text("The order is the widget number: Account 1 is shown by “Agent Usage: Account 1”. Drag, or use ⌥⌘↑ and ⌥⌘↓, to re-order.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.xs)
                    }
                }
            }
            .listStyle(.sidebar)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .up: selectNeighbour(-1)
                case .down: selectNeighbour(1)
                default: break
                }
            }
            Divider()
            HStack(spacing: Spacing.xxs) {
                ToolbarIconButton(symbol: "plus", label: "Add Account") { controller.addingAccount = true }
                ToolbarIconButton(symbol: "minus", label: "Remove Account") {
                    removing = controller.selectedAccountID.flatMap(model.account)
                }
                .disabled(controller.selectedAccountID == nil)
                Divider().frame(height: 16).padding(.horizontal, Spacing.xs)
                ToolbarIconButton(symbol: "chevron.up", label: "Move Up (⌥⌘↑)") { moveSelected(.up) }
                    .disabled(!canMoveSelected(.up))
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                ToolbarIconButton(symbol: "chevron.down", label: "Move Down (⌥⌘↓)") { moveSelected(.down) }
                    .disabled(!canMoveSelected(.down))
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Spacer()
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func selectNeighbour(_ offset: Int) {
        guard !model.accounts.isEmpty else { return }
        let index = controller.selectedAccountID.flatMap { id in model.accounts.firstIndex { $0.id == id } } ?? -offset
        let next = min(max(index + offset, 0), model.accounts.count - 1)
        controller.selectedAccountID = model.accounts[next].id
    }

    private func canMoveSelected(_ direction: AppModel.MoveDirection) -> Bool {
        controller.selectedAccountID.map { model.canMove($0, direction) } ?? false
    }

    private func moveSelected(_ direction: AppModel.MoveDirection) {
        if let id = controller.selectedAccountID { move(id, direction) }
    }

    private func move(_ id: UUID, _ direction: AppModel.MoveDirection) {
        do { try model.move(id, direction) } catch { self.error = error.localizedDescription }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = controller.selectedAccountID, let account = model.account(id) {
            AccountDetailView(
                model: model,
                account: account,
                widgetNumber: model.accounts.firstIndex { $0.id == id }.flatMap { $0 < WidgetSlots.count ? $0 + 1 : nil },
                onReauthorise: { controller.reauthoriseAccountID = account.id },
                onRemove: { removing = account }
            )
            .id(account.id)
        } else if model.accounts.isEmpty {
            ContentUnavailableView {
                Label("No Accounts yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Add a Claude, Codex or Copilot Account. Each one is shown in the menu bar and by its own numbered widget.")
            } actions: {
                Button("Add Account…") { controller.addingAccount = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            ContentUnavailableView("Select an Account", systemImage: "sidebar.left", description: Text("Choose an Account in the list to see its usage and settings."))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Spacing.m) {
            Toggle("Open at login", isOn: Binding(
                get: { controller.loginItem.isEnabled },
                set: { controller.loginItem.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            if let error = controller.loginItem.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Text("Agent Usage \(AppInfo.version) (build \(AppInfo.build))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// An Account in the sidebar: its Provider glyph, name, email, a dot when it needs
/// attention and the number of the widget that shows it.
struct AccountSidebarRow: View {
    let account: Account
    let status: AccountStatus
    let widgetNumber: Int?
    var isSelected = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            ProviderBadge(glyph: account.provider.glyphSystemName, name: account.provider.displayName, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.xs)
            if status != .ok {
                Image(systemName: status.symbol)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : status.color)
                    .help(UsageFormatting.statusText(status))
                    .accessibilityLabel(UsageFormatting.statusText(status))
            }
            WidgetNumberBadge(number: widgetNumber)
                .help(widgetNumber.map { "Shown by the “Agent Usage: Account \($0)” widget" } ?? "Only the first \(WidgetSlots.count) Accounts have a widget")
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// A borderless icon button with a label for VoiceOver and a tooltip.
struct ToolbarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The selected Account: who it is, what its widget shows now, and its Authorisation.
struct AccountDetailView: View {
    let model: AppModel
    let account: Account
    let widgetNumber: Int?
    let onReauthorise: () -> Void
    let onRemove: () -> Void

    @State private var name: String
    @State private var nameError: String?

    init(model: AppModel, account: Account, widgetNumber: Int?, onReauthorise: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.widgetNumber = widgetNumber
        self.onReauthorise = onReauthorise
        self.onRemove = onRemove
        _name = State(initialValue: account.name)
    }

    var body: some View {
        let runtime = model.runtime[account.id]
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let card = model.card(for: account, now: context.date)
            Form {
                Section {
                    header(card: card)
                }

                Section {
                    WidgetPreview(card: card)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                    if let error = runtime?.lastError {
                        Label {
                            Text(error).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Usage")
                        Spacer()
                        Text(widgetNumber.map { "Shown by widget \($0)" } ?? "No widget: only the first \(WidgetSlots.count) Accounts have one")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }

                Section("Account") {
                    TextField("Name", text: $name)
                        .onSubmit(rename)
                    if let nameError {
                        Label(nameError, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if name != account.name {
                        HStack {
                            Spacer()
                            Button("Cancel") { name = account.name; nameError = nil }
                            Button("Rename", action: rename).keyboardShortcut(.defaultAction)
                        }
                    }
                    LabeledContent("Provider", value: account.provider.displayName)
                    LabeledContent("Email") {
                        HStack(spacing: Spacing.xs) {
                            Text(account.email).textSelection(.enabled)
                            if !account.emailVerified {
                                Text("Unverified")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, Spacing.xs + 1)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                    if let organisation = account.organisationName ?? account.organisationID {
                        LabeledContent(account.provider == .codex ? "Plan" : "Organisation", value: organisation)
                    }
                }

                Section("Authorisation") {
                    LabeledContent("Signs in with", value: account.provider.authorisationSummary)
                    if let created = account.authorisationCreatedAt {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let expires = account.authorisationExpiresAt {
                        LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .omitted))
                    }
                    #if DEBUG
                    if account.provider == .fixture {
                        Picker("Fixture scenario", selection: Binding(
                            get: { account.fixtureScenario ?? .normal },
                            set: { scenario in Task { try? await model.setFixtureScenario(scenario, for: account.id) } }
                        )) {
                            ForEach(FixtureScenario.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    #endif
                    HStack {
                        Button("Remove…", role: .destructive, action: onRemove)
                        Spacer()
                        Button {
                            Task { await model.refresh(account.id) }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(runtime?.isFetching ?? false)
                        if card.status.needsAttention {
                            Button("Re-authorise…", action: onReauthorise)
                                .buttonStyle(.borderedProminent)
                                .tint(card.status.color)
                        } else {
                            Button("Re-authorise…", action: onReauthorise)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func header(card: AccountCard) -> some View {
        HStack(spacing: Spacing.l) {
            ProviderBadge(glyph: account.provider.glyphSystemName, name: account.provider.displayName, size: 44)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(account.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("\(account.provider.displayName) · \(account.email)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                StatusChip(status: card.status)
                Text(card.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func rename() {
        do {
            try model.rename(account.id, to: name)
            nameError = nil
        } catch {
            nameError = error.localizedDescription
        }
    }
}

/// The medium widget exactly as it's drawn on the desktop, on a widget-shaped tile.
struct WidgetPreview: View {
    let card: AccountCard

    var body: some View {
        MediumAccountView(card: card)
            .padding(Spacing.xl)
            .frame(width: 344, height: 160)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.widget, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.widget, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Widget preview")
    }
}

extension ProviderKind {
    /// How an Account at this Provider is authorised, in a few words.
    var authorisationSummary: String {
        switch self {
        case .claude: "Claude Code, in its own folder"
        case .codex: "codex login, in its own Codex home"
        case .copilot: "A fine-grained token (Plan: read)"
        case .fixture: "Nothing: canned figures"
        }
    }

    /// One line under the Provider's name in Add Account.
    var addAccountHint: String {
        switch self {
        case .claude: "Sign in with Claude"
        case .codex: "Run codex login"
        case .copilot: "Paste a GitHub token"
        case .fixture: "Canned figures (Debug)"
        }
    }
}
