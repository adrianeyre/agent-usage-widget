# Developing Agent Usage

## Setup

You need Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node 26 and pnpm 12.

```bash
pnpm install                  # the commitlint commit-msg hook, and the website's packages
brew install xcodegen
scripts/generate-project.sh   # writes AgentUsage.xcodeproj from project.yml (not committed)
scripts/create-certificate.sh # once per Mac: the signing certificate, in its own keychain
```

## Commands

| Command | What it does |
|---------|--------------|
| `swift test --package-path AgentUsageCore` | Every unit test: pace maths, display models, Accounts, Providers and the model. |
| `scripts/test.sh` | The unit tests, then Debug and Release builds of both targets, then `check-release-build.sh` (what CI runs). |
| `scripts/dev-install.sh [Debug\|Release]` | Builds, signs and installs to `/Applications`, with a fresh build number and stale widget registrations removed. |
| `scripts/screenshots.sh` | Renders the docs' screenshots into `docs/images/`. |
| `pnpm site:dev` | Serves the website as you edit it. |
| `pnpm site:build` / `pnpm site:preview` | Builds the website into `site/dist/` / serves the build. |
| `pnpm site:typecheck` | Type-checks the website and its demos. |

## Project layout

| Path | What's in it |
|------|--------------|
| `AgentUsageCore/` | Local Swift package. `AgentUsageCore` is the pace maths, colouring, display models and Snapshot files (Foundation only). `AgentUsageViews` is the design system and the widget views and previews. `AgentUsageHostKit` is Accounts, storage, Providers, the refresh loop and the host app's UI. `AgentUsageScreenshots` renders the screenshots. |
| `App/HostApp/` | The menu-bar host app target (not sandboxed). |
| `App/Widget/` | The widget extension target (sandboxed): six numbered widgets and their timeline. |
| `project.yml` | The XcodeGen spec for both targets. |
| `scripts/` | `test.sh`, `dev-install.sh`, `create-certificate.sh`, `sign.sh`, `build-release.sh`, `install.sh`, `screenshots.sh` and the CI keychain scripts. |
| `site/` | The website, published to GitHub Pages (see [Releasing](releasing.md#the-website)). |
| `prototypes/` | Steps and tools for the §11 checks on the Owner's Mac. |
| `docs/` | This guide, the PRD, the ADRs and the screenshots. |

## Previews and Fixture Accounts

- `AgentUsageViews/Previews.swift` has an Xcode preview of every widget state, in both sizes, light and dark (§12 #10).
- Debug builds can add **Fixture** Accounts, which return canned Limits and need no Authorisation. They're compiled out of Release builds, and `scripts/check-release-build.sh` fails if one gets in.

## Screenshots

`scripts/screenshots.sh` runs the `AgentUsageScreenshots` executable, which lays the app's real SwiftUI views out off-screen with sample Accounts and writes 2x PNGs, light and dark, to `docs/images/`. Nothing touches your own Accounts: the model keeps its Accounts in memory and its files in a temporary folder, and no Provider is called. Run it after any UI change and commit the images; the README, this guide and the website all use them. See [Screenshots](screenshots.md) for the full set.

One rendering limit: `NSHostingView.cacheDisplay` can't draw native selection highlights, which is one reason the Manage Accounts sidebar draws its own selection.

## Design

The app's design system (spacing, radii, type, colour roles and shared parts) is in `AgentUsageViews/DesignSystem.swift` and described in [Design](design.md). Use its parts rather than one-off styling.

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org). `fix:` produces a patch release, `feat:` a minor release and `BREAKING CHANGE` a major release. Commitlint checks this in a local `commit-msg` hook and in CI.

## Issues

Tracked in GitHub Issues, using the triage labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human` and `wontfix` (see [`docs/agents/`](../agents/)).
