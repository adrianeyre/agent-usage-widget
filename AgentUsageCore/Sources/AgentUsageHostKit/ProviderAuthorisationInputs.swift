import AgentUsageCore
import AgentUsageViews
import AppKit
import Observation
import SwiftUI

/// Runs `codex login` with `CODEX_HOME` set to one Account's home (U2, ADR-0005). Codex opens
/// the browser and keeps the login in that home; the app never sees a token.
@MainActor
@Observable
public final class CodexLoginSession {
    public enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    public private(set) var state: State = .idle
    private var process: Process?

    public init() {}

    public func start(home: URL) {
        guard state != .running else { return }
        guard let executable = CodexCLI.executable() else {
            state = .failed("Couldn't find the codex CLI. Install Codex, then try again.")
            return
        }
        do { try CodexHomes.prepare(home: home) } catch {
            state = .failed("Couldn't create this Account's Codex folder: \(error.localizedDescription)")
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["login"]
        process.environment = CodexCLI.environment(home: home)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.process = nil
                self.state = status == 0 ? .succeeded : .failed("codex login stopped (exit \(status)).")
            }
        }
        do {
            try process.run()
            self.process = process
            state = .running
        } catch {
            state = .failed("Couldn't start codex login: \(error.localizedDescription)")
        }
    }

    public func cancel() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        if state == .running { state = .idle }
    }
}

/// Signs a Codex Account in, in its own Codex home (U2).
struct CodexLoginInput: View {
    let home: URL
    @Bindable var session: CodexLoginSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            InfoCallout(symbol: "lock.shield.fill", tint: .green, text: "Agent Usage keeps a separate Codex login for this Account, in a folder only it uses. Your everyday Codex login is never used or changed.")
            HStack(spacing: Spacing.m) {
                Button {
                    session.start(home: home)
                } label: {
                    Label("Run codex login", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.state == .running || session.state == .succeeded)
                if session.state == .running {
                    Button("Cancel") { session.cancel() }.controlSize(.large)
                }
            }
            SignInStatus(state: session.state.signInStatus)
        }
        .onDisappear { session.cancel() }
    }
}

/// Takes a Copilot fine-grained personal access token (U1, U2). It's never shown or logged.
struct CopilotTokenInput: View {
    @Binding var token: String
    /// `nil` for a token with no expiry. GitHub's header wins when it reports one (U3).
    @Binding var expiry: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            InfoCallout(symbol: "key.fill", tint: .orange, text: "Create a fine-grained personal access token with no repository access, only the account permission **Plan: read**, and the longest expiry GitHub allows. Then paste it here.")
            Button {
                NSWorkspace.shared.open(CopilotUsageProvider.newTokenURL)
            } label: {
                Label("Open GitHub’s new token page", systemImage: "arrow.up.right.square")
            }
            .controlSize(.large)
            Form {
                SecureField("Token", text: $token, prompt: Text("github_pat_…"))
                if !token.isEmpty, !CopilotToken.looksLikeToken(token) {
                    Label("That doesn't look like a fine-grained token (they start with \(CopilotToken.prefix)).", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if CopilotToken.looksLikeToken(token) {
                    Label("Looks like a fine-grained token", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Toggle("The token expires", isOn: Binding(
                    get: { expiry != nil },
                    set: { expiry = $0 ? Calendar.current.date(byAdding: .year, value: 1, to: Date()) : nil }
                ))
                if let current = expiry {
                    DatePicker("Expires on", selection: Binding(get: { current }, set: { expiry = $0 }), in: Date()..., displayedComponents: .date)
                    Text("As shown on GitHub's token page. Agent Usage warns you 7 days before.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(minHeight: 170)
            .padding(.horizontal, -Spacing.xl)
        }
    }
}

public enum CopilotToken {
    public static let prefix = "github_pat_"

    public static func looksLikeToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(prefix) && trimmed.count > prefix.count + 20
    }
}

/// Runs `claude auth login --claudeai` with `CLAUDE_CONFIG_DIR` set to one Account's folder
/// (U2, ADR-0011). Claude Code opens the browser and keeps the login in that folder's own
/// Keychain item; the app never sees a token. If the browser can't finish the sign-in by
/// itself, Claude Code asks for a code, which the Owner pastes into the app.
@MainActor
@Observable
public final class ClaudeLoginSession {
    public enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// The sign-in page, shown in case the browser didn't open. Never a token.
    public private(set) var signInURL: URL?
    public private(set) var asksForCode = false
    private var process: Process?
    private var input: Pipe?

    public init() {}

    public func start(home: URL) {
        guard state != .running else { return }
        guard let executable = ClaudeCLI.executable() else {
            state = .failed("Couldn't find the claude CLI. Install Claude Code, then try again.")
            return
        }
        do { try ClaudeHomes.prepare(home: home) } catch {
            state = .failed("Couldn't create this Account's Claude Code folder: \(error.localizedDescription)")
            return
        }
        signInURL = nil
        asksForCode = false
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "login", "--claudeai"]
        process.environment = ClaudeCLI.environment(home: home)
        process.currentDirectoryURL = home
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.read(text) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                output.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.input = nil
                self.asksForCode = false
                self.state = status == 0 ? .succeeded : .failed("claude auth login stopped (exit \(status)).")
            }
        }
        do {
            try process.run()
            self.process = process
            self.input = input
            state = .running
        } catch {
            state = .failed("Couldn't start claude auth login: \(error.localizedDescription)")
        }
    }

    private func read(_ text: String) {
        if signInURL == nil, let match = text.firstMatch(of: #/https:\/\/\S+/#) {
            signInURL = URL(string: String(match.0))
        }
        if text.localizedCaseInsensitiveContains("paste code") { asksForCode = true }
    }

    /// Sends a code from the browser to `claude auth login`.
    public func send(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let input else { return }
        input.fileHandleForWriting.write(Data((trimmed + "\n").utf8))
    }

    public func cancel() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        if state == .running { state = .idle }
    }
}

/// Signs a Claude Account in, in its own Claude Code folder (U2, ADR-0011).
struct ClaudeLoginInput: View {
    let home: URL
    @Bindable var session: ClaudeLoginSession
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            InfoCallout(symbol: "lock.shield.fill", tint: .green, text: "Agent Usage keeps a separate Claude Code login for this Account, in a folder only it uses. Sign in with the Claude account you want to track. Your everyday Claude Code login is never used or changed.")
            HStack(spacing: Spacing.m) {
                Button {
                    session.start(home: home)
                } label: {
                    Label("Sign in with Claude", systemImage: "person.badge.key.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.state == .running || session.state == .succeeded)
                if session.state == .running {
                    Button("Cancel") { session.cancel() }.controlSize(.large)
                }
            }
            SignInStatus(state: session.state.signInStatus)
            if session.state == .running, let url = session.signInURL {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text("Browser didn't open?").foregroundStyle(.secondary)
                        Link("Open the sign-in page", destination: url)
                    }
                    Text("To sign in to a different Claude account, sign out of claude.ai in the browser first, or use a private window.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }
            if session.asksForCode {
                HStack {
                    TextField("Code", text: $code, prompt: Text("Paste the code from the browser"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Send", action: send).disabled(code.isEmpty)
                }
            }
        }
        .onDisappear { session.cancel() }
    }

    private func send() {
        session.send(code: code)
        code = ""
    }
}

extension CodexLoginSession.State {
    var signInStatus: SignInStatus.State {
        switch self {
        case .idle: .idle
        case .running: .running
        case .succeeded: .succeeded
        case .failed(let message): .failed(message)
        }
    }
}

extension ClaudeLoginSession.State {
    var signInStatus: SignInStatus.State {
        switch self {
        case .idle: .idle
        case .running: .running
        case .succeeded: .succeeded
        case .failed(let message): .failed(message)
        }
    }
}
