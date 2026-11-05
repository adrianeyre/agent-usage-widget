// How pace works: the medium widget, close up, copied from the Stageshow skill's
// `close-up` gold (one control at about 1.4x, its frame whole across the top) and
// `fade-crop` (it fades out at its foot over filler, the Weekly row).
//
// A system story, no cursor; time passes in the reset text. Beats, about 11s, once:
// 1. resets in 4h 00m: the marker is at 20% and 15% is used. On pace, green.
// 2. 3h 00m: marker 40%, used 46%. Within 10 points over: amber, `over +6%`.
// 3. 2h 00m: marker 60%, used 74%. More than 10 over: red, `over +14%`.
// 4. 1h 00m: the Owner stops; used stays at 74% and the marker moves on to 80%.
//    Payoff: back on pace, green. It holds.
//
// Real strings: Work, Claude · email, Session (5h), the figure, the reset text, the
// pace label. Weekly is filler.
import { Bar, Roll, Stage, Text, type Act } from "../stageshow/kit";
import { BandIcon, ProviderTile, UsageBar, bandOf, paceText } from "./parts";
import { usePageTheme } from "./theme";
import "./pace.css";

interface S {
  step: number;
}

const STEPS = [
  { left: "4h 00m", marker: 20, used: 15 },
  { left: "3h 00m", marker: 40, used: 46 },
  { left: "2h 00m", marker: 60, used: 74 },
  { left: "1h 00m", marker: 80, used: 74 },
] as const;

async function script(a: Act<S>): Promise<void> {
  await a.wait(1000);
  for (let step = 1; step < STEPS.length; step++) {
    a.mark(`step-${step}`);
    await a.set({ step });
    await a.wait(step === STEPS.length - 1 ? 3000 : 2400);
  }
}

export default function PaceDemo() {
  const theme = usePageTheme();
  return (
    <Stage<S>
      width={560}
      height={250}
      compact={{ below: 560, width: 358, height: 200 }}
      initial={{ step: 0 }}
      poster={{ step: 1 }}
      script={script}
      play="once"
      theme={theme}
      className="au pace-demo"
    >
      {(s) => {
        const now = STEPS[s.step] ?? STEPS[0];
        const band = bandOf(now.used, now.marker);
        return (
          <div className="pd-fade">
            <div className="pd-widget">
              <div className="pd-head">
                <ProviderTile kind="claude" size={36} />
                <span className="pd-who">
                  <Text className="pd-name">Work</Text>
                  <Text className="pd-sub">Claude · ada@example.com</Text>
                </span>
                <Text className="pd-updated">Updated just now</Text>
              </div>
              <div className="pd-limit" data-target="session">
                <div className="pd-limit__top">
                  <span className="pd-limit__name">Session (5h)</span>
                  <span className="pd-limit__figure"><Roll>{`${now.used}%`}</Roll></span>
                  <span className="pd-limit__reset">
                    resets in <Roll>{now.left}</Roll>
                  </span>
                </div>
                <div className="pd-limit__bar">
                  <UsageBar used={now.used} marker={now.marker} height={14} />
                  <span className="pd-pace" data-band={band}>
                    <BandIcon band={band} size={15} />
                    <Roll variant="fade">{paceText(now.used, now.marker)}</Roll>
                  </span>
                </div>
              </div>
              <div className="pd-limit pd-limit--filler">
                <div className="pd-limit__top">
                  <span className="pd-limit__name">Weekly</span>
                  <Bar w={44} h={12} tone={3} />
                  <Bar w={100} h={9} tone={2} />
                </div>
                <div className="pd-limit__bar">
                  <span className="pd-filler-bar">
                    <Bar w={160} h={14} r={7} tone={3} />
                  </span>
                  <Bar w={92} h={10} tone={2} />
                </div>
              </div>
            </div>
          </div>
        );
      }}
    </Stage>
  );
}
