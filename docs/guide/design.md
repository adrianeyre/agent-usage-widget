# Design

Agent Usage is a glanceable utility: you look at it for a second and know whether to slow down. Every surface (the widgets, the menu-bar dropdown, Manage Accounts and the sheets) is built from one small design system in `AgentUsageCore/Sources/AgentUsageViews/DesignSystem.swift`.

## Principles

1. **The figure first.** The percentage is the largest thing in each row, in rounded, monospaced digits that don't jitter as they change.
2. **Never colour alone** (C5). Each pace band has a colour, a symbol and words: ✓ green *on pace*, ↗ amber *over +6%*, ! red. Status chips pair a symbol with their text.
3. **Quiet until it matters.** Re-authorise is a small key button until an Account needs it; then it becomes a full-width, tinted button. Stale and expiring states turn orange; everything else stays in neutral greys.
4. **Native, not themed.** SF Pro, SF Symbols and the system's semantic colours, so light and dark mode, Increase Contrast, the accent colour and Reduce Motion all follow the Owner's settings.
5. **Providers are words** (PV4). Each is its name and a neutral glyph on a grey tile, never a logo.

## Tokens

| Token | Values |
|-------|--------|
| `Spacing` | 2, 4, 6, 8, 12, 16, 20 pt (a 4-point scale) |
| `Radius` | badge 6, control 8, card 12, widget 20 (all `.continuous`) |
| `Typeface` | `figureLarge` 22, `figure` 15, `figureSmall` 12 pt: semibold, rounded, monospaced digits |

| Colour role | Value | Used for |
|-------------|-------|----------|
| On pace | `.green` | Fill, ✓ symbol, *ok* status |
| Slightly over / attention | `.orange` | Fill, ↗ symbol, Stale and Re-authorise by. Orange rather than yellow, which fails 4.5:1 on light backgrounds. |
| Well over / failed | `.red` | Fill, ! symbol, Limit reached, Sign in required |
| No pace | `.accentColor` | Fill of a Limit with no Window length (P0) |
| Pace marker | `.primary` | 2 pt wide, 3 pt past the bar, with a hairline halo in the background colour where it crosses the fill |

## Parts

| Part | What it is |
|------|------------|
| `UsageBarView` | The bar and Pace marker (§6.1: about 10 pt, rounded ends). The fill animates unless Reduce Motion is on, and is never narrower than its own height so its rounded end shows. |
| `PaceLabel` | The band's symbol and `on pace` / `over +n%`, or the Limit's state. |
| `ProviderBadge` | A Provider's glyph on a quiet tile, at any size. |
| `StatusChip` | `ok`, `stale`, `Sign in required` or `Re-authorise by …` as a tinted capsule with a symbol. |
| `WidgetNumberBadge` | The number of the widget that shows an Account. |
| `SheetHeader`, `StepIndicator`, `ProviderPicker`, `InfoCallout`, `SignInStatus` | The sheets' title, the *1 Sign in — 2 Details* steps, the Provider cards, explanations set apart from controls, and a sign-in's progress. |

## Accessibility

- Every icon-only button has an accessibility label and a tooltip; decorative symbols are hidden from VoiceOver.
- Each bar is one accessibility element: its name, with its figure, pace and reset time as the value.
- Selected states (sidebar rows, Provider cards) carry the *selected* trait, and arrow keys move the sidebar's selection.
- The website follows the same rules: 4.5:1 contrast, visible focus, 44 pt targets and `prefers-reduced-motion`.

## The website

The website (`site/`) uses the same colour roles on slate neutrals, with Inter and JetBrains Mono. Its product demos are faux UI built on the [Stageshow](https://github.com/benjitaylor/skills) kit, drawn to match the app's views; `site/stageshow/REHEARSAL.md` records how each was checked.
