# PRD: Agent Usage Pace Widget (macOS)

**Status:** Draft v4: multiple Accounts across multiple Providers. Codex and Copilot are built. The Gemini CLI decisions are made, pending its prototype (§7.2).
**Date:** 5 November 2026
**Owner:** Adrian Eyre

Terms in **bold capitals** (Account, Authorisation, Re-authorise, Pace marker, …) are defined in [`GLOSSARY.md`](../../GLOSSARY.md). Decisions are recorded in [`docs/adr/`](../adr/).

---

## 1. Summary

**Agent Usage** is a macOS desktop widget that shows AI subscription plan usage for one or more named **Accounts**. The Accounts can be at different **Providers**: Claude (Anthropic) first, then others such as ChatGPT/Codex (OpenAI), Gemini (Google) and Grok (xAI). Each Account shows the **Limits** its Provider reports. For Claude, these are:

- the **Session limit** (5 hours)
- the **Weekly limit**

Each Limit is drawn as a horizontal progress bar. A **Pace marker** on each bar shows how much usage you would have reached by now if you spread the allowance evenly across the **Window**. When the fill is to the left of the marker, you're on pace. When it's to the right, you're burning faster than the window allows.

Each widget shows one Account, identified by its Provider, its **Account name** and its **Account email**. A menu-bar host app manages the Accounts, fetches their usage and lets you **Re-authorise** each one.

## 2. Problem

Claude's usage page shows how much of each limit you've used, but not whether that rate is sustainable. For example, 60% used could be fine with 30 minutes left in the session, or a problem with 4 hours left. Checking also means opening claude.ai → Settings → Usage, which breaks flow. With several Accounts (e.g. Claude for work, Claude and ChatGPT personally, Gemini), you'd have to repeat that on a different website for each one, while signed in to each.

## 3. Goals

- **At-a-glance status:** each Account's Limits are visible on the desktop without opening a browser.
- **Several Accounts:** track any number of Accounts, each with a name you choose and its email shown.
- **Several Providers:** Accounts can be at any supported Provider. Providers are added one at a time.
- **Pace awareness:** you can instantly see whether current usage is ahead of or behind an even burn rate.
- **Reset awareness:** each bar shows when its window resets.
- **Long-lived authorisation:** each Account stays authorised for as long as its Provider allows (about a year for Claude), and you're warned before it expires.
- **Low maintenance:** the app refreshes itself, updates through one script, and degrades gracefully when data is unavailable.

### Non-goals

- Per-model or per-project usage breakdowns
- Historical charts or usage analytics
- API spend for any Provider (pay-as-you-go billing). Only subscription plan Limits are in scope
- Providers whose usage can only be scraped from a website or estimated (see PV3)
- Alerts or notifications (possible v2, see §13)
- Multiple people sharing one Mac
- Public distribution, the Mac App Store or notarisation

## 4. User

A single person, the **Owner**: a developer with **one or more** AI subscription Accounts, possibly at different Providers (e.g. Claude for work, and ChatGPT and Gemini personally), who uses AI agents heavily during the day and wants to manage pace on each Account without hitting limits mid-task. The Owner runs **macOS 27.0.1**.

## 5. Functional requirements

### 5.1 Accounts

| ID | Requirement |
|----|-------------|
| A1 | An **Account** is one set of usage limits at one **Provider**: an email together with the organisation or plan it uses. The same email may appear in more than one Account (e.g. a personal plan and a Team plan). |
| A2 | Each Account has an **Account name**: required, unique, and editable at any time. When the Account is added, the name is pre-filled with the Account email. |
| A3 | Each Account shows its **Account email**. If the email can be read from the Authorisation, it's read automatically. Otherwise the Owner types it in when adding or re-authorising, and the app notes that it's unverified. |
| A4 | Accounts are added, renamed, re-ordered and removed in **Manage Accounts** in the host app. |
| A5 | Adding an Account that matches an existing one is refused, and the app points to the existing Account. The match uses email and organisation, or email and name when the organisation can't be read. |
| A6 | Removing an Account deletes its Authorisation (its private file, or its Codex home) and deletes its snapshot. For Claude, it puts the original status line back. It never touches the Provider's own CLI or app login. |
| A7 | Each Account's failures stay separate: one Account being stale or needing sign-in never affects the others. |

### 5.2 Authorisation

| ID | Requirement |
|----|-------------|
| U1 | Each Provider defines how its Accounts are authorised:<br>• **Claude:** a Claude Code login held by Claude Code in a dedicated Claude Code folder owned by the app, one for each Account (ADR-0011).<br>• **Codex:** a ChatGPT login held by Codex in a dedicated Codex home owned by the app, one for each Account (ADR-0005).<br>• **Copilot:** a fine-grained personal access token with only the *Plan: read* permission and a one-year expiry (or the longest GitHub allows), kept in a private file owned by the app (ADR-0006, ADR-0010).<br>• **Gemini CLI:** a Google login held by Gemini CLI in a dedicated Gemini CLI home owned by the app, one for each Account (ADR-0007). |
| U2 | **Re-authorise** runs the Provider's own sign-in flow:<br>• **Claude:** runs `CLAUDE_CONFIG_DIR=<Account's folder> claude auth login --claudeai` from Agent Usage. The Owner approves in the browser.<br>• **Codex:** runs `CODEX_HOME=<Account's folder> codex login`.<br>• **Copilot:** opens GitHub's new fine-grained token page and asks the Owner to paste the replacement.<br>• **Gemini CLI:** runs Gemini CLI's Google sign-in with its home set to the Account's folder. |
| U3 | When an Authorisation's expiry is known, its Account's widget and menu row show `Re-authorise by <date>` from **7 days** before expiry.<br>• **Claude:** Claude Code refreshes the login itself, so there's no warning, only `Sign in required` when it's signed out.<br>• **Copilot:** expiry is read from GitHub's `github-authentication-token-expiration` response header, which GitHub sends only for tokens that expire. If it's absent, the expiry the Owner entered when adding or re-authorising is used, or there's no warning for a token with no expiry.<br>• **Codex** and **Gemini CLI:** the login has no known expiry, so there's no warning, only `Sign in required` when authentication fails. |
| U4 | Every Account always has a **Re-authorise** button in its menu-bar row and in Manage Accounts. |
| U5 | When an Account's widget shows `Sign in required`, tapping it opens the host app with that Account selected. |
| U6 | **Hard rule, for every Provider:** the app never reads, refreshes or rewrites a login it doesn't own, such as Claude Code's, the Codex CLI's or the Gemini CLI's stored login. Every Authorisation lives only in storage the app owns: its own private files (ADR-0010), or the dedicated Claude Code, Codex and Gemini CLI folders (ADR-0011, ADR-0005, ADR-0007). |

### 5.3 Providers

| ID | Requirement |
|----|-------------|
| PV1 | Providers are added in this order, each with its own prototype ticket and release, so one Provider's undocumented API never holds up the rest:<br>1. **Claude** (Anthropic)<br>2. **Codex** (OpenAI ChatGPT plans)<br>3. **GitHub Copilot**<br>4. **Gemini CLI** (Google): **deferred**. The Owner's account can't sign in to Gemini CLI (#36). The plan is in ADR-0007<br>A Provider the Owner doesn't subscribe to is skipped. |
| PV2 | Each Provider reports its own **Limits**. Each Limit has a name, a Window length (if known) and a reset time.<br>• **Claude:** the Session limit (5h) and the Weekly limit (7d).<br>• **Codex:** named from their window length, e.g. `5h` and `Weekly`. ChatGPT Pro has no 5h limit, so it shows Weekly only.<br>• **Copilot:** one Limit, **Monthly credits**, whose Window is the calendar month in UTC, so the Pace marker uses that month's actual length. Copilot Free has no credits, so it shows its monthly `Chat` and `Completions` allowances instead (ADR-0006).<br>• **Gemini CLI:** **Pro daily** and **Flash daily**, each with a 24-hour Window ending at its reset time (ADR-0007). |
| PV3 | A Provider is supported only if a program can read **real** usage figures from it, through an API, response headers, a CLI or a local file. The source can be official or unofficial, as long as that Provider's ADR records how fragile it is. Providers that could only be scraped from a website with a browser cookie, or estimated from request counts, are left out (R6). |
| PV4 | The Provider is shown as **text** (e.g. `Claude`, `ChatGPT`, `Gemini`, `Grok`) with a neutral glyph. No company logos are bundled. |
| PV5 | **Not supported** (no source that meets PV3 has been found):<br>• the **Gemini app**: no programmatic route<br>• **xAI Grok / SuperGrok**: no usage API, and the Grok Build CLI has no published quotas<br>• **Cursor**: usage is readable only through the Admin API, for Enterprise teams<br>• **Mistral Le Chat** and **Perplexity**: no API for checking usage<br>There's no plan to check these again. An issue can reopen one if a usable source appears. |
| PV6 | **Account email** for Copilot: the GitHub username (`@username`), plus the primary email when the token can read it. |

### 5.4 Bars

| ID | Requirement |
|----|-------------|
| F1 | Show one labelled horizontal progress bar for each of the Account's Limits: up to two on the medium widget and on the small widget. For Claude, these are **Session (5h)** and **Weekly**. |
| F2 | Each bar fills from left to right according to the percentage of the limit used (0–100%). |
| F3 | Each bar shows the percentage used as text, e.g. `42%`. |
| F4 | Each bar shows the time until reset, e.g. `resets in 2h 14m` or `resets Mon 09:00` (medium widget only). |

### 5.5 Pace marker

| ID | Requirement |
|----|-------------|
| P0 | A Pace marker is drawn only on a Limit whose Window length is known. A Limit without one shows its bar and percentage with no marker or pace colouring. |
| P1 | Each bar has a thin marker line drawn across the bar (perpendicular to it) at the **expected-usage position**. |
| P2 | Expected usage = `elapsed time in window ÷ total window length`. |
| P2a | In general, elapsed time = `window length − time until reset`. P3 and P4 are Claude's cases. |
| P3 | For the session bar, the window length is 5 hours, and elapsed time = `5h − time until reset`. |
| P4 | For the weekly bar, the window length is 7 days, and elapsed time = `7d − time until reset`. |
| P5 | The marker moves on every refresh, even if the usage figure itself hasn't changed. |
| P6 | If there is no active session (no reset time returned), hide the session marker and show `No active session`. |

**Worked example:** a session reset is 2h 00m away, so 3h of the 5h window has elapsed. The marker sits at 60%. If usage is 45%, you're on pace. If usage is 75%, you're over pace.

### 5.6 Pace colouring

| ID | Requirement |
|----|-------------|
| C1 | **On pace** (usage ≤ marker): the fill is green. |
| C2 | **Slightly over pace** (usage ≤ marker + 10 percentage points): the fill is amber. |
| C3 | **Well over pace** (usage > marker + 10 pp) **or usage ≥ 90%**: the fill is red. |
| C4 | The threshold (10 pp) is a single constant that's easy to change. |
| C5 | Colour must not be the only signal: show a small text label too, `on pace` / `over +12%`. |

### 5.7 Refresh and data states

| ID | Requirement |
|----|-------------|
| R1 | The host app fetches usage for each Account every 5 minutes by default, and immediately on **Refresh now**. After each fetch, it asks WidgetKit to reload the widgets' timelines. The interval can be changed with a `UserDefaults` value (`defaults write`), with no settings UI in v1 (§13). |
| R2 | The widget recomputes the marker position on every timeline entry, from the stored reset time, even if the latest fetch failed. |
| R3 | Show `Updated 3m ago` in small text. |
| R4 | If an Account's data is stale (> 30 min), dim its bars and show a warning icon. |
| R5 | If an Account's Authorisation fails or is revoked, show `Sign in required` for that Account instead of zeros (see U5). |
| R6 | Never show fabricated or estimated usage figures. If the data is missing, say so. |

## 6. Layout

### 6.1 Widgets

Each widget instance shows **one** Account, at any Provider. The gallery offers **Agent Usage: Account 1** to **Account 6**, and each one shows the Account at that position in Manage Accounts (ADR-0009). To see several Accounts (e.g. Claude Work, ChatGPT and Gemini), place several numbered widgets. Moving an Account up or down in Manage Accounts changes which widget shows it. A widget whose position has no Account shows `No Account <n>` and a hint to add or move one. It never falls back to another Account. (A per-widget **Edit Widget** picker needs App Intents, which refuse a build with no Team ID.)

Medium widget (approx. 340 × 160 pt):

```
 Claude · Work · you@example.com        Updated 2m ago
 ───────────────────────────────────────────────────
 Session (5h)                    45%   resets 2h 00m
 [███████████████░░░░░│░░░░░░░░░░░░░░]  on pace
                      ↑ marker at 60%

 Weekly                          71%   resets Mon 09:00
 [████████████████████████░│░░░░░░░░░]  over +8%
                          ↑ marker at 63%
```

- Header: the Provider name and glyph, then the Account name in primary text, then the Account email in smaller secondary text. If the email is too long, it's cut short in the middle (e.g. `firstname.lastname@exa…le.com`).
- Bar height: about 10 pt, rounded ends.
- Marker: 2 pt wide, extending 3 pt above and below the bar, in the primary label colour so it shows over both filled and empty track.
- Supports light and dark mode.

Small widget: the Provider glyph, the Account name and up to two bars only, with no email and no reset text.

### 6.2 Menu-bar host app

The menu-bar icon is a plain glyph with no numbers next to it. Clicking it opens a dropdown:

- One row per Account, in the order set in Manage Accounts. Each row shows the Provider, Account name, Account email, the % used of each Limit, and the status (`ok` / `stale` / `Sign in required` / `Re-authorise by …`), plus a **Re-authorise** button.
- **Manage Accounts…** opens a window to add, rename, re-order and remove Accounts. It also has the **Open at login** switch and the About section (version and build number).
- **Refresh now**
- **Quit**

## 7. Data source

Most Providers have no official public API for subscription-plan usage limits, so the data source is the main risk for each one.

### 7.1 Claude

Each Claude Account has its own Claude Code folder, owned by the app and signed in from Agent Usage with `claude auth login` (ADR-0011). Every fetch runs Claude Code's local `/usage` command there (`claude -p /usage --output-format json`). It makes no model request and spends no allowance. The Session and Weekly figures, with their reset times, are read from its text, which is fragile if Claude Code changes the wording.

History: `claude setup-token` tokens can't read usage, because they lack `user:profile` (#16, ADR-0003). The status-line feed that came next (ADR-0008) needed signing in inside Claude Code and switching `/login` between accounts.

## 7.2 Other Providers

Research as of 5 November 2026. **[O]** = official, **[U]** = unofficial or reverse-engineered. PV1 sets the order and PV5 lists what's unsupported.

- **Codex** reads usage by starting `codex app-server` for each fetch (ADR-0005). The `codex` CLI must be installed.
- **Copilot** reads usage from Copilot's internal `copilot_internal/user` endpoint using the Account's PAT (ADR-0006). The documented billing API has no monthly allowance, so it can't give a percentage.
- **Gemini CLI** reads usage through the internal `retrieveUserQuota` method, with the login Gemini CLI holds in the Account's own home (ADR-0007).

| Provider | Limits | How usage could be read | Authorisation | Fit with PV3 |
|----------|--------|-------------------------|---------------|--------------|
| **OpenAI**: Codex (ChatGPT plans) | 5h (Plus, not Pro) + weekly | `codex app-server` JSON-RPC `account/rateLimits/read`: `usedPercent`, `windowDurationMins`, `resetsAt` (in OpenAI's repo, but the schema is marked unstable) | ChatGPT OAuth managed by Codex itself. Its refresh tokens rotate, so the app must never refresh them (U6) | Good: real figures with Window and reset |
| **GitHub Copilot** | Monthly AI credits, reset on the 1st at 00:00 UTC | `copilot_internal/user` **[U]**: `entitlement`, `remaining`, `quota_reset_date_utc`. The billing REST API **[O]** reports usage but no allowance | PAT with an expiry you set, no rotation | Good: real figures. Fragile (ADR-0006) |
| **Google**: Gemini CLI / Code Assist | Requests per day (+ per-minute caps) | Internal `retrieveUserQuota` endpoint **[U]**: remaining fraction + reset | Google OAuth; whether it rotates is unknown | Eligible (unofficial is allowed under PV3) and planned last, on the Owner's AI Pro plan (ADR-0007). In June 2026, Antigravity CLI replaced Gemini CLI for unpaid and Google One users |
| **Google**: Gemini app | 5h + weekly (compute-based) | None found | — | Fails PV3 |
| **xAI**: SuperGrok / Grok Build | Weekly | None found | — | Fails PV3 |
| **Cursor** | Monthly | Admin API, for Enterprise teams only | Admin key | Fails PV3 for individuals |
| **Mistral** Le Chat, **Perplexity** | Daily / unclear | None found | — | Fails PV3 |

### 7.3 Provider interface

The fetching code for each Provider sits behind a single `UsageProvider` interface, so Providers can be added or swapped without touching the UI:

```swift
struct LimitUsage {
    let name: String              // e.g. "Session (5h)", "Weekly"
    let percentUsed: Double?      // 0–100
    let windowLength: TimeInterval?  // nil → no Pace marker (P0)
    let resetsAt: Date?
}

struct UsageSnapshot {
    let accountID: UUID
    let limits: [LimitUsage]      // in display order; the widget shows up to two
    let fetchedAt: Date
}

protocol UsageProvider {
    func fetch(for account: Account) async throws -> UsageSnapshot
}
```

Requirements:

- Each Authorisation lives only in storage the app owns (U6). It's never written anywhere except the Account's private file (`host/authorisations/<id>`, mode 600, ADR-0010), never logged, never put in a snapshot, and never sent anywhere except that Provider's own endpoints.
- The app never reads, refreshes or rewrites a login it doesn't own (U6). Refresh-token rotation would log the Provider's own CLI out.
- Each provider handles schema changes defensively: missing fields produce `nil`, not crashes.

## 8. Technical approach

**Native WidgetKit (SwiftUI)**, deployment target **macOS 26**, supported on **macOS 27.0.1**.

- **Host app** (ADR-0002): a non-sandboxed menu-bar app that opens at login (`SMAppService`, on by default, can be turned off). It holds the Authorisations, fetches usage for every Account, writes one snapshot per Account and reloads the widget timelines.
- **Widget extension:** sandboxed. Its TimelineProvider only reads snapshots and produces entries every 5 minutes so the pace marker moves between fetches. It never makes network calls or touches Authorisations.
- **Data sharing without an App Group** (ADR-0004): snapshots are written to the host app's Application Support folder. The widget reads them through a read-only `temporary-exception.files.home-relative-path.read-only` entitlement for that path. Each snapshot holds the Account name and email for the widget header, but no Authorisation.
- **Signing** (ADR-0004): both targets are signed with one **self-signed code-signing certificate** (`Agent Usage Self-Signed`). There's no paid Apple Developer membership, Team ID, provisioning profile or notarisation.

The pace calculation and colouring logic must be platform-independent and unit-tested.

## 9. Build, release and install

| ID | Requirement |
|----|-------------|
| B1 | GitHub Actions runs on the pinned **`macos-26`** arm64 image with its stable Xcode 26. It moves to an Xcode 27 image once one reaches general availability, or sooner if the macOS 27 SDK is needed. |
| B2 | Every pull request, and every release run, builds the app and runs the unit tests. A release is published only if everything passes. |
| B3 | Every push to `main` runs **semantic-release**. Conventional Commits decide the version (`fix:` → patch, `feat:` → minor, `BREAKING CHANGE` → major). Releases come from `main` only, with no prerelease channels. |
| B4 | Commit messages are checked by **commitlint**, both in a local Husky `commit-msg` hook and in CI on pull requests. |
| B5 | The release version is written into `MARKETING_VERSION`, and the GitHub run number becomes `CURRENT_PROJECT_VERSION`. |
| B6 | CI imports the self-signed certificate from two repo secrets (the `.p12` in base64, and its password) into a temporary keychain, and signs both targets with it. |
| B7 | Each GitHub release has `AgentUsage-<version>.zip` (the `.app`, zipped with `ditto`) and a SHA-256 checksum file attached. |
| B8 | Release notes appear on the GitHub release and are prepended to `CHANGELOG.md`, which semantic-release commits to `main` as `chore(release): <version> [skip ci]`. That's the only automated commit on `main`, and the release tag `v<version>` points at it. |
| B9 | `scripts/install.sh` installs the latest release, or a version you name. It uses `gh release download`, which avoids the quarantine flag. It checks the SHA-256, quits the host app, replaces `/Applications/Agent Usage.app` and relaunches it. It's the only supported way to install. |

The repo is `adrianeyre/agent-usage-widget`, renamed from `claude-usage-indicator` once development is complete. It's private, so GitHub bills its macOS runner minutes at 10× the Linux rate.

## 10. Edge cases

| Case | Behaviour |
|------|-----------|
| Usage at or above 100% | Bar full and red; text reads `Limit reached · resets in …` |
| Reset time in the past (stale data) | Treat the window as reset: marker at 0%, show stale warning until the next successful fetch |
| No active 5h session | Session bar empty, no marker, `No active session` |
| Clock or time zone change | All maths uses absolute `Date` values, so no special handling is needed |
| Mac asleep through a reset | The next refresh recomputes from scratch |
| Network offline | Keep the last snapshot, move the marker, show stale state after 30 min |
| Host app not running | No new data arrives. Markers keep moving and the stale state appears after 30 min |
| Authorisation revoked or expired | That Account shows `Sign in required`, and the other Accounts are unaffected |
| Account removed while a widget shows it | The widget shows the Account that's now at its position, or `No Account <n>` |
| Same email in two organisations | Two separate Accounts with different names |
| Same email at two Providers | Two separate Accounts, told apart by their Provider |
| A Limit with no known Window length | Bar and percentage only, with no Pace marker or pace colouring (P0) |
| Provider reports more than two Limits | The first two in the Provider's display order are shown |
| Release opened from a browser download | Gatekeeper blocks it, which is expected. Use `scripts/install.sh` |

## 11. First ticket: prove it works

This ticket covers Claude and the shared app plumbing. Each later Provider gets its own prototype ticket (PV1).

Before the real Claude Provider is built, a throwaway prototype on the Owner's Mac (**macOS 27.0.1**) checks the following. Work that doesn't depend on its answers can go ahead alongside it: the repo and CI foundations, the pace logic, the widget views, and app UI driven by a debug-only fixture data source that returns canned Limits and is never in a release build.

1. A `claude setup-token` token can read session and weekly usage with reset times.
2. The token can read the Account's email and organisation.
3. The host app can run `claude setup-token` and capture the token, or else pasting it in is required.
4. What happens when the token is revoked.

**Result (#16):** check 1 failed. Setup tokens get 403 for lacking `user:profile`. After a new grilling session, Claude moved to the status line feed (ADR-0008), and then, so that Accounts are signed in from the app, to a dedicated Claude Code folder for each Account, read with Claude Code's local `/usage` (ADR-0011). That makes checks 3 and 4 moot.
5. A widget extension with a self-signed signature shows up in the widget gallery and runs.
6. The read-only sandbox exception can read the host app's snapshot file.
7. The host app can reload the widget's timelines.
8. Updating to a new build signed with the same certificate doesn't bring back Keychain prompts.

If 1, 5, 6 or 7 fails, **stop and grill again** before choosing a fallback. Failures of 2 and 3 have fallbacks already decided (A3, U2).

### Later Provider tickets

- **Codex prototype:**
  - `codex app-server` against a dedicated `CODEX_HOME` returns `usedPercent`, `windowDurationMins` and `resetsAt`.
  - `codex login` works in that folder.
  - Codex can store credentials in the Keychain.
  - The Owner's everyday `~/.codex` login is left untouched.
- **Copilot prototype:**
  - The billing endpoint still reports usage since the switch to credits in June 2026.
  - *Plan: read* is enough permission.
  - The `github-authentication-token-expiration` header is present.
  - The username, and the email if allowed, can be read.
- **Gemini CLI prototype:**
  - Gemini CLI can be pointed at a dedicated home, and its Google sign-in works there.
  - `retrieveUserQuota` returns Pro and Flash buckets, each with a remaining fraction and a reset time, for an AI Pro Account.
  - Whether the refresh token rotates, and that the Owner's everyday Gemini CLI login is left untouched.
  - How to read the Account email.

## 12. Acceptance criteria

All criteria are checked on **macOS 27.0.1**.

1. For each Account, its bars render with percentages that match that Provider's own usage page within one refresh cycle.
2. With a reset 2h away on the 5h bar, the marker sits at 60% (±1%).
3. With a weekly reset 3.5 days away, the weekly marker sits at 50% (±1%).
4. Fill colour changes from green to amber to red at the defined thresholds, and the text label matches.
5. Disconnecting the network for 35 minutes shows the stale state, and the markers keep moving.
6. Revoking one Account's Authorisation shows `Sign in required` for that Account only, not 0%, and Re-authorise fixes it.
7. Two Accounts can be added with different names, and each widget shows the chosen Account's name and email.
8. Adding a duplicate Account is refused.
9. An Authorisation within 7 days of expiry shows `Re-authorise by <date>`.
10. The widget is legible in both light and dark mode.
11. Unit tests cover the pace calculation, including window boundaries (0%, 100%, past reset).
12. `scripts/install.sh` installs a CI-built release that launches without Gatekeeper or Keychain prompts.

## 13. Future ideas (v2)

- Notification when usage crosses the Pace marker by more than a set margin.
- "Projected usage at reset" figure, based on the recent burn rate.
- Menu-bar text summary (`5h 45% · wk 71%`).
- API spend tracking (pay-as-you-go), e.g. through the OpenAI Admin API or the xAI Management API.
- A large widget that stacks every Account.
- Configurable threshold and refresh interval in the host app.
- A DMG release.
- Moving to a paid Developer ID: App Group, notarisation, and normal opening of downloads (would replace ADR-0004).

## 14. Resolved questions

1. **Data source:** Claude Code's local `/usage` command, in a dedicated Claude Code folder for each Account, signed in from Agent Usage (ADR-0011). Setup tokens can't read usage (#16), and the status-line feed (ADR-0008) needed signing in inside Claude Code.
2. **Platform:** WidgetKit, macOS 26 deployment target, run on macOS 27.0.1.
3. **Widget size:** medium and small.
4. **Distribution:** personal use only, self-signed, installed from private GitHub releases by script (ADR-0004).
5. **Providers:** subscription plan Limits only. Claude first, then one Provider at a time, only where real usage figures can be read (PV1–PV3).
6. **Name:** the app is **Agent Usage**, and the repo becomes `agent-usage-widget`.
7. **Provider order:** Claude, then Codex, then Copilot, then Gemini CLI. Providers the Owner doesn't use are skipped (PV1).
8. **Unofficial sources:** allowed when the figures are real and the risk is recorded in an ADR (PV3). Gemini CLI is eligible but goes last.
9. **Unsupported Providers:** the Gemini app, xAI Grok, Cursor (for individuals), Mistral and Perplexity (PV5).
10. **Copilot source:** `copilot_internal/user`, because the billing API has no allowance (ADR-0006).
11. **Gemini CLI:** the Owner's AI Pro plan, a dedicated Gemini CLI home for each Account, and Pro daily and Flash daily Limits (ADR-0007).

## 15. Open questions

1. Gemini CLI, if the Owner's account can ever sign in: whether its refresh token rotates, and how to read `retrieveUserQuota` without reading its token (ADR-0007).
