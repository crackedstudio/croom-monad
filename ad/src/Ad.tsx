/**
 * The 30-second product advertisement.
 *
 * Two rules it holds itself to, both because the product does:
 *
 * The price line is real. `points.json` is 49 closes from Room 0x29bcf64c, derived from drand
 * beacon rounds by the specification the contracts implement. An advert for a protocol about not
 * fabricating numbers should not fabricate its own.
 *
 * The refusal is real. `LeafNotCommitted(21193065)` is the error the deployed Ladder actually
 * returns for a price that is not in the committed batch, at the round shown, and 99.999827 is the
 * honest close it does accept.
 */
import { loadFont } from "@remotion/fonts";
import { Audio } from "@remotion/media";
import {
  AbsoluteFill,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import POINTS from "./points.json";
import { ACCENT, BAD, DIM, GOOD, INK, RULE, TEXT } from "./theme";

// Loaded from disk rather than from Google Fonts: the network fetch stalls `delayRender` in the
// render browser, and these are the exact files the logo was rasterised with, so the ad and the
// brand cannot drift apart.
const display = "Chakra Petch";
const mono = "JetBrains Mono";

void Promise.all([
  loadFont({ family: display, url: staticFile("ChakraPetch-Bold.ttf"), weight: "700" }),
  loadFont({ family: mono, url: staticFile("JetBrainsMono-Regular.ttf"), weight: "400" }),
  loadFont({ family: mono, url: staticFile("JetBrainsMono-Bold.ttf"), weight: "700" }),
]);

const W = 1920;
const H = 1080;

/** The visible grid the brand uses, so the ad sits in the same world as the site. */
const Grid: React.FC = () => (
  <AbsoluteFill style={{ opacity: 0.5 }}>
    <svg width={W} height={H}>
      {Array.from({ length: Math.floor(W / 120) + 1 }, (_, i) => (
        <line key={`v${i}`} x1={i * 120} y1={0} x2={i * 120} y2={H} stroke={RULE} strokeWidth={1} />
      ))}
      {Array.from({ length: Math.floor(H / 120) + 1 }, (_, i) => (
        <line key={`h${i}`} x1={0} y1={i * 120} x2={W} y2={i * 120} stroke={RULE} strokeWidth={1} />
      ))}
    </svg>
  </AbsoluteFill>
);

/** Rises into place, in the brutalist system: no fade-and-float mush. */
const Line: React.FC<{
  children: React.ReactNode;
  delay?: number;
  size?: number;
  color?: string;
  font?: string;
  tracking?: number;
  weight?: number;
}> = ({ children, delay = 0, size = 64, color = TEXT, font = display, tracking = 0, weight = 700 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: frame - delay, fps, config: { damping: 200 }, durationInFrames: 18 });
  return (
    <div
      style={{
        fontFamily: font,
        fontSize: size,
        fontWeight: weight,
        color,
        letterSpacing: tracking,
        lineHeight: 1.12,
        opacity: enter,
        transform: `translateY(${interpolate(enter, [0, 1], [26, 0])}px)`,
      }}
    >
      {children}
    </div>
  );
};

/** The real price series, drawing itself left to right. */
const Path: React.FC<{ box: [number, number, number, number]; delay?: number; draw?: number; width?: number }> = ({
  box,
  delay = 0,
  draw = 50,
  width = 7,
}) => {
  const frame = useCurrentFrame();
  const [bx, by, bw, bh] = box;
  const d = (POINTS as [number, number][])
    .map(([x, y], i) => `${i ? "L" : "M"}${(bx + x * bw).toFixed(1)},${(by + y * bh).toFixed(1)}`)
    .join("");

  // An over-long dash length, scrubbed to zero: the stroke appears to be drawn.
  const LEN = 6000;
  const offset = interpolate(frame - delay, [0, draw], [LEN, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
      <path
        d={d}
        fill="none"
        stroke={ACCENT}
        strokeWidth={width}
        strokeLinejoin="round"
        strokeLinecap="round"
        strokeDasharray={LEN}
        strokeDashoffset={offset}
      />
    </svg>
  );
};

const Pad: React.FC<{ children: React.ReactNode; y?: number }> = ({ children, y = 300 }) => (
  <AbsoluteFill style={{ padding: "0 180px", justifyContent: "flex-start", paddingTop: y }}>
    {children}
  </AbsoluteFill>
);

// ── scenes ───────────────────────────────────────────────────────────────────────────────────

const Hook: React.FC = () => (
  <AbsoluteFill>
    <Path box={[180, 420, 1560, 340]} draw={64} />
    <Pad y={180}>
      <Line delay={10} size={128} tracking={-2}>A PRICE</Line>
      <Line delay={18} size={128} tracking={-2}>NOBODY DECIDES</Line>
    </Pad>
    <AbsoluteFill style={{ padding: "0 180px", justifyContent: "flex-end", paddingBottom: 170 }}>
      <Line delay={46} size={27} font={mono} color={DIM} tracking={5} weight={400}>
        49 REAL CLOSES, DERIVED FROM A PUBLIC RANDOMNESS BEACON
      </Line>
    </AbsoluteFill>
  </AbsoluteFill>
);

const NotAnOracle: React.FC = () => {
  const rows: [string, string][] = [
    ["NOT AN ORACLE", "nobody reports it"],
    ["NOT A FEED", "nothing to go down"],
    ["NOT US", "we cannot move it either"],
  ];
  return (
    <Pad y={300}>
      <Line size={96} tracking={-1}>WHERE THE PRICE COMES FROM</Line>
      <div style={{ height: 70 }} />
      {rows.map(([big, small], i) => (
        <div key={big} style={{ display: "flex", alignItems: "baseline", gap: 40, marginBottom: 34 }}>
          <Line delay={16 + i * 13} size={62} color={ACCENT}>{big}</Line>
          <Line delay={20 + i * 13} size={34} font={mono} color={DIM} weight={400}>{small}</Line>
        </div>
      ))}
    </Pad>
  );
};

const Beacon: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  // One pulse every three seconds, because that is the beacon's actual period.
  const beat = Math.floor(frame / (3 * fps));
  const since = frame - beat * 3 * fps;
  const pulse = interpolate(since, [0, 10], [1, 0], { extrapolateRight: "clamp" });

  return (
    <Pad y={320}>
      <Line size={96} tracking={-1}>EVERY THREE SECONDS,</Line>
      <Line delay={8} size={96} tracking={-1}>THE WORLD SIGNS A NUMBER</Line>
      <div style={{ height: 64 }} />
      <div style={{ display: "flex", gap: 22, alignItems: "center" }}>
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <div
            key={i}
            style={{
              width: 104,
              height: 104,
              border: `2px solid ${i === beat % 6 ? ACCENT : RULE}`,
              background: i === beat % 6 ? `rgba(139,124,255,${0.18 + pulse * 0.5})` : "transparent",
            }}
          />
        ))}
      </div>
      <div style={{ height: 46 }} />
      <Line delay={26} size={30} font={mono} color={DIM} tracking={4} weight={400}>
        DRAND · LEAGUE OF ENTROPY · NOBODY CAN PREDICT OR SKIP IT
      </Line>
    </Pad>
  );
};

/** The hero beat: a lie put in front of the contract that pays people. */
const Rig: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const refusedAt = Math.round(3.4 * fps);
  const stamp = spring({ frame: frame - refusedAt, fps, config: { damping: 14, stiffness: 180 } });
  const shown = frame < Math.round(1.7 * fps) ? "99.999827" : "99.999827000000000001";
  const changed = frame >= Math.round(1.7 * fps);

  return (
    <Pad y={210}>
      <Line size={92} tracking={-1}>SO CHANGE ONE.</Line>
      <div style={{ height: 52 }} />

      <div style={{ border: `2px solid ${RULE}`, padding: "42px 48px", maxWidth: 1360 }}>
        <Line size={26} font={mono} color={DIM} tracking={5} weight={400}>
          ROUND 21,193,065 · CLOSE
        </Line>
        <div style={{ height: 22 }} />
        <div
          style={{
            fontFamily: mono,
            fontSize: 72,
            fontWeight: 700,
            color: changed ? BAD : TEXT,
            letterSpacing: -1,
          }}
        >
          {shown}
        </div>
        <div style={{ height: 18 }} />
        <div style={{ fontFamily: mono, fontSize: 28, color: DIM, opacity: changed ? 1 : 0 }}>
          moved by 10⁻¹⁸ — the smallest lie this encoding can express
        </div>
      </div>

      <div style={{ height: 44 }} />
      <Line delay={Math.round(2.4 * fps)} size={30} font={mono} color={DIM} tracking={4} weight={400}>
        ASKING Ladder.provenClose — THE CALL THAT SETTLES MARKETS
      </Line>

      <div
        style={{
          marginTop: 44,
          opacity: stamp,
          transform: `scale(${interpolate(stamp, [0, 1], [1.25, 1])})`,
          display: "inline-block",
        }}
      >
        <div
          style={{
            fontFamily: mono,
            fontWeight: 700,
            fontSize: 52,
            color: BAD,
            border: `3px solid ${BAD}`,
            padding: "20px 34px",
            letterSpacing: 3,
          }}
        >
          REFUSED — LeafNotCommitted(21193065)
        </div>
      </div>
    </Pad>
  );
};

const Payout: React.FC = () => (
  <Pad y={300}>
    <Line size={96} tracking={-1}>AND IT PAYS OUT</Line>
    <div style={{ height: 24 }} />
    <Line delay={8} size={36} font={mono} color={DIM} weight={400}>
      settled against two prices proved to belong to a finalised batch
    </Line>
    <div style={{ height: 72 }} />
    <div style={{ display: "flex", gap: 120, alignItems: "flex-end" }}>
      <div>
        <Line delay={20} size={28} font={mono} color={DIM} tracking={5} weight={400}>STAKED</Line>
        <Line delay={24} size={104} font={mono} color={TEXT}>0.02</Line>
      </div>
      <div>
        <Line delay={34} size={28} font={mono} color={DIM} tracking={5} weight={400}>RECEIVED</Line>
        <Line delay={38} size={104} font={mono} color={GOOD}>0.0495</Line>
      </div>
    </div>
    <div style={{ height: 54 }} />
    <Line delay={52} size={28} font={mono} color={DIM} tracking={4} weight={400}>
      NO ORACLE WAS CONSULTED · 1% RAKE, PUBLISHED UP FRONT
    </Line>
  </Pad>
);

const End: React.FC<{ url: string }> = ({ url }) => (
  <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
    <Path box={[460, 300, 1000, 190]} draw={30} width={9} />
    <div style={{ marginTop: 300, textAlign: "center" }}>
      <Line delay={10} size={190} tracking={14}>CROOM</Line>
      <div style={{ height: 26 }} />
      <Line delay={20} size={32} font={mono} color={ACCENT} tracking={9} weight={700}>
        DERIVED, NOT REPORTED
      </Line>
      <div style={{ height: 58 }} />
      <Line delay={30} size={34} font={mono} color={DIM} tracking={3} weight={400}>
        {url} · LIVE ON MONAD TESTNET
      </Line>
    </div>
  </AbsoluteFill>
);

// ── the cut ──────────────────────────────────────────────────────────────────────────────────

export const Ad: React.FC = () => {
  const { fps } = useVideoConfig();
  const s = (n: number) => Math.round(n * fps);

  // Replace with the deployed URL once Pages is live.
  const url = "croom.pages.dev";

  return (
    <AbsoluteFill style={{ backgroundColor: INK }}>
      {/* Synthesised by make-audio.py. It pulses every three seconds because the beacon does. */}
      <Audio src={staticFile("soundtrack.wav")} />
      <Grid />
      <Sequence from={0} durationInFrames={s(5.5)} premountFor={s(1)}>
        <Hook />
      </Sequence>
      <Sequence from={s(5.5)} durationInFrames={s(4.5)} premountFor={s(1)}>
        <NotAnOracle />
      </Sequence>
      <Sequence from={s(10)} durationInFrames={s(5)} premountFor={s(1)}>
        <Beacon />
      </Sequence>
      <Sequence from={s(15)} durationInFrames={s(7)} premountFor={s(1)}>
        <Rig />
      </Sequence>
      <Sequence from={s(22)} durationInFrames={s(4.5)} premountFor={s(1)}>
        <Payout />
      </Sequence>
      <Sequence from={s(26.5)} durationInFrames={s(3.5)} premountFor={s(1)}>
        <End url={url} />
      </Sequence>
    </AbsoluteFill>
  );
};
