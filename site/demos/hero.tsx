// The hero: the menu-bar dropdown, as the app draws it (docs/images/menu.png).
// Copied from the Stageshow skill's `hero-demo` gold (one product surface on the
// page's own ground, named targets, a cursor that does one thing) with
// `subscriptions`' values changing on their own rows.
//
// Beats, about 9 seconds, played once as it scrolls in:
// 1. The dropdown is open under the gauge in the menu bar. Work's session is 52%,
//    green, under its Pace marker at 60%.
// 2. The cursor goes to Refresh now and presses it (⌘R).
// 3. The header says Refreshing…; the figures roll. Work's session reaches 66% and
//    crosses its marker: the fill turns amber and its symbol says over.
// 4. Payoff: the cursor rests on the row and its tooltip reads `over +6% ·
//    resets in 2h 00m`, which is what the app's own .help says. It holds.
//
// Real strings: the header, the three Account names, Work's email and limits, the
// figures, the tooltip and the three menu items. Other emails are filler.
import { Gauge, Power, RefreshCw, UsersRound, Wifi } from "lucide-react";
import { Bar, Roll, Spinner, Stage, States, Text, Tooltip, type Act, type Layout } from "../stageshow/kit";
import { BandIcon, ProviderTile, UsageBar, bandOf, type ProviderKind } from "./parts";
import { usePageTheme } from "./theme";
import "./hero.css";

interface S {
  refreshing: boolean;
  /** The fetch has landed: the new figures and "Updated just now". */
  fresh: boolean;
  tip: boolean;
}

const START: S = { refreshing: false, fresh: false, tip: false };
const POSTER: S = { refreshing: false, fresh: true, tip: false };

interface Limit {
  name: string;
  before: number;
  after: number;
  marker: number;
  target?: string;
}

interface Card {
  kind: ProviderKind;
  provider: string;
  name: string;
  email: string | null;
  limits: [Limit, Limit];
}

const CARDS: Card[] = [
  {
    kind: "claude",
    provider: "Claude",
    name: "Work",
    email: "ada@example.com",
    limits: [
      { name: "Session (5h)", before: 52, after: 66, marker: 60, target: "work-session" },
      { name: "Weekly", before: 38, after: 41, marker: 50 },
    ],
  },
  {
    kind: "claude",
    provider: "Claude",
    name: "Personal",
    email: null,
    limits: [
      { name: "Session (5h)", before: 30, after: 34, marker: 52 },
      { name: "Weekly", before: 49, after: 51, marker: 56 },
    ],
  },
  {
    kind: "codex",
    provider: "Codex",
    name: "ChatGPT",
    email: null,
    limits: [
      { name: "5h", before: 18, after: 24, marker: 28 },
      { name: "Weekly", before: 52, after: 53, marker: 54 },
    ],
  },
];

async function script(a: Act<S>): Promise<void> {
  await a.wait(900);
  a.mark("refresh");
  await a.move("refresh");
  await a.wait(250);
  await a.click("refresh");
  await a.set({ refreshing: true });
  await a.wait(1100);
  a.mark("land");
  await a.set({ refreshing: false, fresh: true });
  await a.wait(1300);
  await a.move("work-session", { duration: 700 });
  await a.wait(500);
  a.mark("tip");
  await a.set({ tip: true });
  await a.wait(3200);
}

function AccountCard({ card, s, compact }: { card: Card; s: S; compact: boolean }) {
  return (
    <div className="hm-card">
      <div className="hm-card__head">
        <ProviderTile kind={card.kind} size={28} />
        <span className="hm-card__who">
          <Text className="hm-card__name">{card.name}</Text>
          {card.email ? (
            <Text className="hm-card__sub">{`${card.provider} · ${card.email}`}</Text>
          ) : (
            <span className="hm-card__sub">
              {card.provider} · <Bar w={compact ? 96 : 120} h={6} tone={2} />
            </span>
          )}
        </span>
        <span className="hm-chip">
          <BandIcon band="green" size={11} />
          ok
        </span>
      </div>
      {card.limits.map((limit) => {
        const used = s.fresh ? limit.after : limit.before;
        const band = bandOf(used, limit.marker);
        return (
          <div key={limit.name} className="hm-limit" data-target={limit.target}>
            <span className="hm-limit__name">{limit.name}</span>
            <UsageBar used={used} marker={limit.marker} />
            <span className="hm-limit__figure">
              <BandIcon band={band} size={12} />
              <Roll>{`${used}%`}</Roll>
            </span>
          </div>
        );
      })}
    </div>
  );
}

function Dropdown({ s, layout }: { s: S; layout: Layout }) {
  const compact = layout === "compact";
  const cards = compact ? CARDS.slice(0, 2) : CARDS;
  return (
    <div className="hm-panel">
      <div className="hm-head">
        <span className="hm-app" aria-hidden>
          <Gauge strokeWidth={2.4} />
        </span>
        <span className="hm-head__text">
          <Text className="hm-head__title">Agent Usage</Text>
          <States
            className="hm-head__sub"
            align="start"
            value={s.refreshing ? "busy" : s.fresh ? "fresh" : "old"}
            states={{
              old: `${cards.length} Accounts · Updated 5m ago`,
              busy: "Refreshing…",
              fresh: `${cards.length} Accounts · Updated just now`,
            }}
          />
        </span>
        <span className="hm-head__spin" data-show={s.refreshing || undefined}>
          <Spinner size={14} />
        </span>
      </div>
      <div className="hm-cards">
        {cards.map((card) => (
          <AccountCard key={card.name} card={card} s={s} compact={compact} />
        ))}
      </div>
      <div className="hm-actions">
        <div className="hm-action" data-target="refresh" data-cursor="pointer">
          <RefreshCw strokeWidth={2} />
          <span>Refresh now</span>
          <kbd>⌘R</kbd>
        </div>
        <div className="hm-action">
          <UsersRound strokeWidth={2} />
          <span>Manage Accounts…</span>
          <kbd>⌘,</kbd>
        </div>
        <div className="hm-action-rule" />
        <div className="hm-action">
          <Power strokeWidth={2} />
          <span>Quit Agent Usage</span>
          <kbd>⌘Q</kbd>
        </div>
      </div>
    </div>
  );
}

export default function HeroDemo() {
  const theme = usePageTheme();
  return (
    <Stage<S>
      width={460}
      height={560}
      compact={{ below: 460, width: 358, height: 470 }}
      initial={START}
      poster={POSTER}
      script={script}
      play="once"
      theme={theme}
      cursor={{ at: { wide: { x: 236, y: 548 }, compact: { x: 190, y: 458 } }, style: "real" }}
      className="au hero-menu"
    >
      {(s, rect, layout) => (
        <>
          <div className="hm-menubar">
            <span className="hm-menubar__left">
              <Bar w={34} h={7} tone={4} />
              <Bar w={40} h={7} tone={3} />
              <Bar w={30} h={7} tone={3} />
              <Bar w={46} h={7} tone={3} />
            </span>
            <span className="hm-menubar__right">
              <span className="hm-menubar__item" data-on>
                <Gauge strokeWidth={2.2} />
              </span>
              <Wifi strokeWidth={2.2} className="hm-menubar__icon" />
              <Text className="hm-menubar__clock">Thu 09:41</Text>
            </span>
          </div>
          <Dropdown s={s} layout={layout} />
          <Tooltip show={s.tip} at={rect("work-session")} side="below" gap={8} className="hm-tip">
            over +6% · resets in 2h 00m
          </Tooltip>
        </>
      )}
    </Stage>
  );
}
