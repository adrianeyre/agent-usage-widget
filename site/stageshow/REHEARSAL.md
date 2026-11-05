# Rehearsal: the website's demos

Filmed with the Stageshow skill's `scripts/film.mjs` (headless Chrome, from a scratch
copy of the skill, never in this repository) against `pnpm site:dev`, with `--gate`,
at 1440 and 390 wide, in light and dark. Full-page screenshots of the built page
(`pnpm site:preview`) were taken at 1440 and 390, light and dark, with reduced motion
on, so every demo showed its poster.

Every demo ends `rehearsal passed` at both widths and in both themes.

## Hero, `demos/hero.tsx` (once, about 9s)

Gold: `hero-demo` (one product surface on the page's ground, named targets, a cursor
that does one thing) with `subscriptions`' values changing on their own rows.
Changed: the app's menu-bar dropdown (`docs/images/menu.png`) hanging from the gauge in
a menu bar that runs off both sides; three Accounts wide, two compact (358).
Beats: rest … Refresh now pressed … Refreshing… … the figures roll, Work's session
reaches 66% past its marker at 60% and turns amber … the cursor rests on the row and
its tooltip (the app's own `.help`) reads `over +6% · resets in 2h 00m` (payoff,
held 3.2s). Poster: after the refresh, the amber row, no tooltip.
Fixed on the way: `Count`'s digit strips re-homing after a roll was reported as a
settle snap (replaced by `Roll`, which animates only the changed characters); the
band symbol popped between check and arrow (all three now stay mounted and
crossfade); the header's text sat 4px off the cards' text; the hovered menu row's
icon was translucent; the Work email was cut at 390 (shortened).

## How pace works, `demos/pace.tsx` (once, about 11s)

Gold: `close-up` (the medium widget at 1.45x) with `fade-crop` (it fades out at its
foot over the Weekly row, which is filler). A system story, no cursor.
Beats: 4h 00m left, 15% against a 20% marker, on pace … 3h, 46% against 40%, over
+6%, amber … 2h, 74% against 60%, over +14%, red … 1h, usage holds at 74% while the
marker moves on to 80%: on pace (payoff, held 3s). Poster: the amber beat, which
shows the marker and the fill disagreeing.

## Features bento, `demos/bento.tsx` (one beat each, once)

Gold: `bento`. Providers (collection: the three built Providers' bars fill), Numbered
widgets (`many-of-one`: widgets 1 to 6 off the tile's foot and right edge, only number
2 with words), Private by design (diagram: app → snapshots → sandboxed widget with no
network). The menu-bar and logins tiles are page type.
Fixed: the widgets ran a sliver past the foot (now well past), and on phones the last
widget showed 4px at the right edge (the column count now leaves a readable third or
none); the Providers bars had collapsed in their column; a 0% fill drew as a dot; the
focused widget's rows were spaced too loosely for its height (a footer line fills it).

## Not checked

- Real Safari: filmed and screenshotted in Chrome only.
- The `kit override` lines that `film.mjs` prints for the kit's own phone rules on the
  built bundle (the bundler merges the kit's CSS with the page's). No demo draws a
  phone, and on the dev server the lines don't appear, as ai-office's rehearsal found.
