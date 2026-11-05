// The pictures in the features bento grid, one Stage per tile, from the Stageshow
// skill's `bento` gold. The grid, the tiles and their copy are page HTML
// (index.html, styles.css); each picture measures its slot and draws at 1:1,
// pinned to the tile's foot. The tile list, written before any was built:
//
//   Tile        Span   Kind        The one thing                       Moves
//   Providers   1 × 1  Collection  Claude, Codex, Copilot, side by side the bars fill
//   Widgets     2 × 1  Many-of-one numbered widgets 1–6, one in focus   (still)
//   Private     1 × 1  Diagram     the widget only reads a folder      (still)
//
// No windows in the grid: the hero has the only one.
import { useLayoutEffect, useRef, useState, type RefObject } from "react";
import { FileJson, FolderLock, Gauge, WifiOff } from "lucide-react";
import { Bar, Stage, Text, type Act } from "../stageshow/kit";
import { ProviderTile, UsageBar, type ProviderKind } from "./parts";
import { usePageTheme } from "./theme";
import "./bento.css";

interface Beat {
  on: boolean;
}
const before: Beat = { on: false };
const after: Beat = { on: true };
const beat = async (a: Act<Beat>): Promise<void> => {
  await a.wait(450);
  await a.set({ on: true });
};

/** The slot's width, kept as the tile reflows, so the Stage draws at 1:1. */
function useSlotWidth(fallback: number): [RefObject<HTMLDivElement | null>, number] {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(fallback);
  useLayoutEffect(() => {
    const node = ref.current?.parentElement;
    if (!node) return;
    const measure = () => setWidth(Math.max(1, Math.round(node.getBoundingClientRect().width)));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  return [ref, width];
}

/* ---------------- Providers ---------------- */

const PROVIDERS: { kind: ProviderKind; name: string; used: number; marker: number }[] = [
  { kind: "claude", name: "Claude", used: 45, marker: 60 },
  { kind: "codex", name: "Codex", used: 61, marker: 56 },
  { kind: "copilot", name: "Copilot", used: 24, marker: 37 },
];

export function ProvidersTile() {
  const theme = usePageTheme();
  const [ref, width] = useSlotWidth(340);
  return (
    <div ref={ref}>
      <Stage<Beat> width={width} height={184} initial={before} poster={after} play="once" script={beat} theme={theme} className="au bt-providers">
        {(s) => (
          <div className="bt-list">
            {PROVIDERS.map((p) => (
              <div key={p.kind} className="bt-provider">
                <ProviderTile kind={p.kind} size={30} />
                <span className="bt-provider__body">
                  <Text className="bt-provider__name">{p.name}</Text>
                  <UsageBar used={s.on ? p.used : 0} marker={p.marker} />
                </span>
              </div>
            ))}
          </div>
        )}
      </Stage>
    </div>
  );
}

/* ---------------- Numbered widgets ---------------- */

export function WidgetsTile() {
  const theme = usePageTheme();
  const [ref, width] = useSlotWidth(700);
  const compact = width < 520;
  // Whole widgets from the left gutter, then one cut by the edge only if a readable
  // part of it (60px or more) shows; never a sliver.
  const pitch = 164;
  const room = width - 24;
  const whole = Math.floor((room + 14) / pitch);
  const count = Math.min(6, room - whole * pitch >= 60 ? whole + 1 : whole);
  return (
    <div ref={ref}>
      <Stage<Beat> width={width} height={compact ? 200 : 220} initial={before} poster={after} play="once" script={beat} theme={theme} className="au bt-widgets">
        {(s) => (
          <div className="bt-grid" style={{ gridTemplateColumns: `repeat(${count}, 150px)` }}>
            {Array.from({ length: count }, (_, i) => {
              const focus = i === 1;
              return (
                <div key={i} className="bt-widget" data-focus={focus || undefined}>
                  <span className="bt-widget__head">
                    <span className="bt-widget__number">{i + 1}</span>
                    {focus ? <Text className="bt-widget__name">Personal</Text> : <Bar w={56} h={7} tone={3} />}
                  </span>
                  {focus ? (
                    <>
                      <span className="bt-widget__row">
                        <span>Session (5h)</span>
                        <b>{s.on ? "34%" : "30%"}</b>
                      </span>
                      <UsageBar used={s.on ? 34 : 30} marker={52} />
                      <span className="bt-widget__row">
                        <span>Weekly</span>
                        <b>51%</b>
                      </span>
                      <UsageBar used={51} marker={56} />
                      <span className="bt-widget__foot">Updated just now</span>
                    </>
                  ) : (
                    <>
                      <Bar w={110} h={6} tone={2} />
                      <Bar w={118} h={8} r={4} tone={2} />
                      <Bar w={96} h={6} tone={2} />
                      <Bar w={118} h={8} r={4} tone={2} />
                      <Bar w={70} h={5} tone={1} />
                    </>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </Stage>
    </div>
  );
}

/* ---------------- Private by design ---------------- */

export function PrivateTile() {
  const theme = usePageTheme();
  const [ref, width] = useSlotWidth(340);
  return (
    <div ref={ref}>
      <Stage<Beat> width={width} height={184} initial={after} theme={theme} className="au bt-private">
        {() => (
          <div className="bt-flow">
            <span className="bt-node">
              <span className="bt-node__icon bt-node__icon--app">
                <Gauge strokeWidth={2.4} />
              </span>
              <Text className="bt-node__label">Agent Usage</Text>
            </span>
            <span className="bt-link" />
            <span className="bt-node">
              <span className="bt-node__icon">
                <FileJson strokeWidth={2} />
              </span>
              <Text className="bt-node__label">Snapshots</Text>
            </span>
            <span className="bt-link" />
            <span className="bt-node">
              <span className="bt-node__icon">
                <FolderLock strokeWidth={2} />
              </span>
              <Text className="bt-node__label">Widget</Text>
              <span className="bt-node__off">
                <WifiOff strokeWidth={2.4} />
              </span>
            </span>
          </div>
        )}
      </Stage>
    </div>
  );
}
