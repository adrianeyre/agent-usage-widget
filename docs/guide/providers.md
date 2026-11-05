# Providers

Agent Usage adds Providers one at a time, and only where real usage figures can be read by a program. Usage that can only be scraped or estimated is never shown (R6). Each Provider appears as text with a neutral glyph, never a logo (PV4).

| # | Provider | Status | Limits shown | Authorised with |
|---|----------|--------|--------------|-----------------|
| 1 | Claude (Anthropic) | Built | Session (5h), Weekly | **Sign in with Claude** in Agent Usage: Claude Code's login in a folder dedicated to that Account (ADR-0011) |
| 2 | OpenAI Codex (ChatGPT plans) | Built | `5h` (not on Pro), `Weekly` | `codex login` in a Codex home dedicated to that Account (ADR-0005) |
| 3 | GitHub Copilot | Built | Monthly credits (Copilot Free: Chat, Completions) | Fine-grained PAT with *Plan: read* only, up to a year (ADR-0006) |
| 4 | Google Gemini CLI | Deferred: the Owner's account can't sign in (#36) | Pro daily, Flash daily (planned) | Gemini CLI login in a dedicated home (ADR-0007) |
| — | Gemini app, xAI Grok, Cursor, Mistral, Perplexity | Not supported: no readable usage data | — | — |

## Claude

The figures come from Claude Code's `/usage`, run headless in the Account's own folder: `claude -p /usage --output-format json` is a local command with no turns and no cost. Usage is only available on Pro, Max and Ultra plans. `claude auth status --json` gives the email and organisation, and tells a signed-out folder apart. Earlier approaches (one-year setup tokens, the status line feed) are recorded as superseded in ADR-0003 and ADR-0008.

## Codex

The app reads the Account's ChatGPT usage with the login in its own Codex home. Limits are named from their Window length: `5h`, `Weekly`, `Daily`, otherwise whole hours or days. Pro plans have no 5-hour Limit.

## Copilot

GitHub's documented billing API reports what was used but not the monthly allowance, so it can't give a percentage. The app reads `copilot_internal/user` instead, which is undocumented and may change (ADR-0006). Copilot Free has no premium credits, so a Free Account shows its monthly Chat and Completions allowances. The Window is the UTC calendar month.

## Gemini CLI (deferred)

Planned to use a Gemini CLI login in a dedicated home with `GEMINI_FORCE_FILE_STORAGE=true` (its Keychain item otherwise ignores the home). Deferred until an account can sign in (ADR-0007, #36).

More detail is in [PRD §5.3](../product-requirements-document/agent-usage-widget.md#53-providers) and [§7.2](../product-requirements-document/agent-usage-widget.md#72-other-providers). What cost time with each Provider is in [Troubleshooting](troubleshooting.md#providers).
