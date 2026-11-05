// The app's own small parts, drawn as the SwiftUI views draw them (AgentUsageViews,
// docs/guide/design.md): the Provider tile with its neutral glyph (PV4: never a logo),
// the bar with its 2pt Pace marker, and the band's symbol, so pace never reads by
// colour alone (C5).
import type { CSSProperties, ReactNode } from "react";
import { ArrowUpRight, Check, CircleAlert, CodeXml, Sparkle, SquareTerminal } from "lucide-react";
import "./parts.css";

export type Band = "green" | "amber" | "red";
export type ProviderKind = "claude" | "codex" | "copilot";

/** C1–C3: amber within 10 points over the marker, red past that or at 90% and above. */
export function bandOf(used: number, marker: number): Band {
  if (used >= 90 || used > marker + 10) return "red";
  if (used > marker) return "amber";
  return "green";
}

/** C5: `on pace` or `over +6%`, never `over +0%`. */
export function paceText(used: number, marker: number): string {
  return used > marker ? `over +${Math.max(1, Math.round(used - marker))}%` : "on pace";
}

const GLYPHS: Record<ProviderKind, ReactNode> = {
  claude: <Sparkle strokeWidth={2.2} />,
  codex: <SquareTerminal strokeWidth={2} />,
  copilot: <CodeXml strokeWidth={2.2} />,
};

export function ProviderTile({ kind, size = 28 }: { kind: ProviderKind; size?: number }) {
  return (
    <span className="au-tile" style={{ "--au-tile-size": `${size}px` } as CSSProperties} aria-hidden>
      {GLYPHS[kind]}
    </span>
  );
}

/** All three symbols stay mounted and crossfade, so a band change never pops. */
export function BandIcon({ band, size = 12 }: { band: Band; size?: number }) {
  return (
    <span className="au-band-icon" data-band={band} style={{ width: size, height: size }} aria-hidden>
      <Check strokeWidth={3.5} data-for="green" />
      <ArrowUpRight strokeWidth={3.5} data-for="amber" />
      <CircleAlert strokeWidth={0} data-for="red" />
    </span>
  );
}

/** The bar: fill in its band's colour, the marker at the expected-usage position. */
export function UsageBar({ used, marker, height = 6, className }: { used: number; marker: number; height?: number; className?: string }) {
  const band = bandOf(used, marker);
  return (
    <span
      className={`au-bar${className ? ` ${className}` : ""}`}
      data-band={band}
      data-empty={used <= 0 || undefined}
      style={{ "--au-bar-h": `${height}px`, "--au-used": `${Math.min(used, 100)}%`, "--au-marker-at": `${marker}%` } as CSSProperties}
    >
      <span className="au-bar__fill" />
      <span className="au-bar__marker" />
    </span>
  );
}
