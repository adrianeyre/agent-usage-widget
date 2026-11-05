# Stageshow kit (vendored)

The React kit from the [Stageshow skill](https://github.com/benjitaylor/skills) by
Benji Taylor (MIT, see `LICENSE` and `NOTICE.md`), which the website's product demos
in `site/demos/` are built on. `kit/` is copied as published (skill version 1.1.1),
unmodified: restyle it from `site/demos/` (`look.css` maps the app's colours onto the
kit's tokens), never by editing it, so it can be replaced by a newer copy whole.
`site/demos/tsconfig.json` checks it under plain `strict`.

The kit's own brand artwork in `kit/brands/` keeps the sources and licences listed in
`kit/brands/SOURCES.md`. The website uses none of it: Providers are shown as text and
a neutral glyph, never a logo (PRD PV4).

`REHEARSAL.md` records how each demo was rehearsed with the skill's filming tools.
