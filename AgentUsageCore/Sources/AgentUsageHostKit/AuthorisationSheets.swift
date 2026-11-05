import AgentUsageCore
import AgentUsageViews
import AppKit
import SwiftUI

/// Add Account (A2, A3, A5, U2).
struct AddAccountSheet: View {
    let model: AppModel
    let onAdded: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Step { case authorise, details }

    /// Chosen up front so a Codex Account's home can be prepared before it signs in.
    @State private var accountID = UUID()
    @State private var provider: ProviderKind = .claude
    @State private var step: Step = .authorise
    @State private var token = ""
    @State private var copilotExpiry: Date? = Calendar.current.date(byAdding: .year, value: 1, to: Date())
    @State private var claudeLogin = ClaudeLoginSession()
    @State private var codexLogin = CodexLoginSession()
    @State private var added = false
    @State private var email = ""
    @State private var emailVerified = false
    @State private var organisationID: String?
    @State private var organisationName: String?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var fixtureScenario: FixtureScenario = .normal
    @State private var checking = false
    @State private var notice: String?
    @State private var error: String?
    @State private var duplicate: Account?

    private var needsAuthorisation: Bool { provider != .fixture }
    private var codexHome: URL { CodexHomes().home(for: accountID) }
    private var claudeHome: URL { ClaudeHomes().home(for: accountID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SheetHeader(
                title: "Add Account",
                subtitle: "Each Account is shown in the menu bar and by its own numbered widget."
            ) {
                if needsAuthorisation {
                    StepIndicator(steps: ["Sign in", "Details"], current: step == .authorise ? 0 : 1)
                }
            }

            if model.providers.addableProviders.count > 1 {
                ProviderPicker(providers: model.providers.addableProviders, selection: $provider)
                    .disabled(step == .details && needsAuthorisation)
                    .onChange(of: provider) { _, new in
                        token = ""
                        step = new == .fixture ? .details : .authorise
                        if new == .fixture {
                            email = "fixture@example.com"
                            emailVerified = true
                            if !nameEdited { name = email }
                        }
                    }
            }

            Group {
                if step == .authorise && needsAuthorisation {
                    switch provider {
                    case .claude: ClaudeLoginInput(home: claudeHome, session: claudeLogin)
                    case .codex: CodexLoginInput(home: codexHome, session: codexLogin)
                    case .copilot: CopilotTokenInput(token: $token, expiry: $copilotExpiry)
                    case .fixture: EmptyView()
                    }
                } else {
                    details
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let notice {
                InfoCallout(symbol: "info.circle.fill", tint: .blue, text: notice)
            }
            if let error {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if let duplicate {
                        Button("Show “\(duplicate.name)”") {
                            onAdded(duplicate.id)
                            dismiss()
                        }
                    }
                }
            }

            Divider()
            HStack {
                if step == .details && needsAuthorisation {
                    Text("Signed in. Check the details, then add the Account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if step == .authorise && needsAuthorisation {
                    Button {
                        checkAuthorisation()
                    } label: {
                        if checking {
                            HStack(spacing: Spacing.s) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Continue")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!authorisationReady || checking)
                } else {
                    Button("Add Account", action: add)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(Spacing.xxl + 4)
        .frame(width: 560)
        .onChange(of: provider) { old, _ in
            if old == .codex { discardCodexHome() }
            if old == .claude { discardClaudeHome() }
        }
        .onDisappear {
            if !added {
                discardCodexHome()
                discardClaudeHome()
            }
        }
    }

    private var authorisationReady: Bool {
        switch provider {
        case .claude: claudeLogin.state == .succeeded
        case .codex: codexLogin.state == .succeeded
        case .copilot: CopilotToken.looksLikeToken(token)
        case .fixture: true
        }
    }

    @ViewBuilder
    private var details: some View {
        Form {
            if needsAuthorisation {
                Label(emailVerified ? "Signed in as \(email)" : "Signed in", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            }
            TextField("Account email", text: $email)
                .disabled(emailVerified && provider != .fixture)
                .onChange(of: email) { _, new in if !nameEdited { name = new } }
            TextField("Account name", text: Binding(get: { name }, set: { name = $0; nameEdited = true }), prompt: Text("e.g. Work or Personal"))
            if let organisationName {
                LabeledContent(provider == .codex ? "Plan" : "Organisation", value: organisationName)
            }
            #if DEBUG
            if provider == .fixture {
                Picker("Fixture scenario", selection: $fixtureScenario) {
                    ForEach(FixtureScenario.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(minHeight: 150)
        .padding(.horizontal, -Spacing.xl)
    }

    /// Reads the email and organisation from the Authorisation (A3, PV6). If they can't be
    /// read, the Owner types the email in and it's marked unverified.
    private func checkAuthorisation() {
        checking = true
        error = nil
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        let home = codexHome
        let claude = claudeHome
        Task {
            do {
                let identity = try await AccountIdentity.read(provider: provider, token: token, codexHome: home, claude: claude)
                email = identity.email
                emailVerified = true
                organisationID = identity.organisationID
                organisationName = identity.organisationName
                notice = nil
            } catch {
                email = ""
                emailVerified = false
                organisationID = nil
                organisationName = nil
                notice = "The email couldn't be read from this Authorisation. Type it in; it will be shown as unverified."
            }
            if !nameEdited { name = email }
            checking = false
            step = .details
        }
    }

    private func add() {
        let candidate = Account(
            id: accountID,
            provider: provider,
            name: name,
            email: email,
            emailVerified: emailVerified,
            organisationID: organisationID,
            organisationName: organisationName,
            enteredAuthorisationExpiry: provider == .copilot ? copilotExpiry : nil,
            fixtureScenario: provider == .fixture ? fixtureScenario : nil
        )
        let secret: String? = switch provider {
        case .copilot: token.trimmingCharacters(in: .whitespacesAndNewlines)
        case .claude, .codex, .fixture: nil
        }
        do {
            let added = try model.add(candidate, authorisation: secret)
            self.added = true
            Task { await model.refresh(added.id) }
            onAdded(added.id)
            dismiss()
        } catch let accountError as AccountError {
            error = accountError.localizedDescription
            if case .duplicate(let existing) = accountError { duplicate = existing } else { duplicate = nil }
        } catch {
            self.error = error.localizedDescription
            duplicate = nil
        }
    }

    /// A Claude Code folder made for an Account that was never added is signed out and deleted.
    private func discardClaudeHome() {
        guard !added else { return }
        claudeLogin.cancel()
        let account = Account(id: accountID, provider: .claude, name: "", email: "", emailVerified: false)
        Task { await ClaudeUsageProvider().forget(account) }
    }

    /// A Codex home made for an Account that was never added is signed out and deleted.
    private func discardCodexHome() {
        guard !added else { return }
        codexLogin.cancel()
        let account = Account(id: accountID, provider: .codex, name: "", email: "", emailVerified: false)
        Task { await CodexUsageProvider().forget(account) }
    }
}

/// The email and organisation read from a new Authorisation (A3, A5, PV6).
struct AccountIdentity {
    var email: String
    var organisationID: String?
    var organisationName: String?

    static func read(provider: ProviderKind, token: String, codexHome: URL, claude: URL) async throws -> AccountIdentity {
        switch provider {
        case .claude:
            let status = try await ClaudeUsageProvider.status(home: claude)
            guard status.loggedIn, let email = status.email else { throw UsageProviderError.unexpectedResponse("no email") }
            return AccountIdentity(email: email, organisationID: status.organisationID, organisationName: status.organisationName)
        case .codex:
            let profile = try await CodexUsageProvider.fetchProfile(home: codexHome)
            guard let email = profile.email else { throw UsageProviderError.unexpectedResponse("no email") }
            // The plan or workspace tells two Accounts with one email apart (A1, A5).
            let plan = profile.workspaceName ?? profile.planType.map { "ChatGPT \($0.capitalized)" }
            return AccountIdentity(email: email, organisationID: plan.map { "codex:\($0)" }, organisationName: plan)
        case .copilot:
            let profile = try await CopilotUsageProvider.fetchProfile(token: token)
            return AccountIdentity(email: profile.accountEmail, organisationID: profile.userID.map { "github:\($0)" }, organisationName: nil)
        case .fixture:
            return AccountIdentity(email: "fixture@example.com")
        }
    }
}

/// Re-authorise (U2, U4): replaces the stored Authorisation and its creation date.
struct ReauthoriseSheet: View {
    let model: AppModel
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var copilotExpiry: Date? = Calendar.current.date(byAdding: .year, value: 1, to: Date())
    @State private var codexLogin = CodexLoginSession()
    @State private var claudeLogin = ClaudeLoginSession()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SheetHeader(title: "Re-authorise \(account.name)", subtitle: "\(account.provider.displayName) · \(account.email)") {
                ProviderBadge(glyph: account.provider.glyphSystemName, name: account.provider.displayName, size: 32)
            }
            switch account.provider {
            case .claude:
                ClaudeLoginInput(home: ClaudeHomes().home(for: account.id), session: claudeLogin)
                hint("Sign in as \(account.email).")
            case .codex:
                CodexLoginInput(home: CodexHomes().home(for: account.id), session: codexLogin)
                hint("Sign in in the browser as \(account.email).")
            case .copilot:
                CopilotTokenInput(token: $token, expiry: $copilotExpiry)
                hint("Create the token while signed in to GitHub as \(account.email).")
            case .fixture:
                InfoCallout(symbol: "testtube.2", tint: .secondary, text: "A fixture Account needs no Authorisation. Re-authorising resets its scenario to normal.")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !ready)
            }
        }
        .padding(Spacing.xxl + 4)
        .frame(width: 560)
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "person.crop.circle")
            .labelStyle(CompactLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var ready: Bool {
        switch account.provider {
        case .claude: claudeLogin.state == .succeeded
        case .codex: codexLogin.state == .succeeded
        case .copilot: CopilotToken.looksLikeToken(token)
        case .fixture: true
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                switch account.provider {
                case .claude:
                    try await model.reauthorise(account.id, with: nil)
                case .copilot:
                    try await model.reauthorise(account.id, with: token.trimmingCharacters(in: .whitespacesAndNewlines), enteredExpiry: copilotExpiry)
                case .codex:
                    try await model.reauthorise(account.id, with: nil)
                case .fixture:
                    try await model.reauthorise(account.id, with: nil, fixtureScenario: .normal)
                }
                dismiss()
            } catch {
                NSLog("Agent Usage: Re-authorise failed: %@", error.localizedDescription)
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
