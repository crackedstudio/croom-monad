import { loadFont } from "@remotion/fonts";
import { Video } from "@remotion/media";
import {
  AbsoluteFill,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import CAPTIONS from "./founder-captions.json";
import POINTS from "./points.json";
import { ACCENT, BAD, DIM, GOOD, INK, PANEL, RULE, TEXT } from "./theme";

const display = "Chakra Petch";
const mono = "JetBrains Mono";

void Promise.all([
  loadFont({ family: display, url: staticFile("ChakraPetch-Bold.ttf"), weight: "700" }),
  loadFont({ family: mono, url: staticFile("JetBrainsMono-Regular.ttf"), weight: "400" }),
  loadFont({ family: mono, url: staticFile("JetBrainsMono-Bold.ttf"), weight: "700" }),
]);

type Caption = {
  text: string;
  startMs: number;
  endMs: number;
  timestampMs: number | null;
  confidence: number | null;
};

type Clip = {
  src: string;
  seconds: number;
  title: string;
  kicker: string;
  layout: "wide" | "portrait";
  panel: "identity" | "problem" | "app" | "proof";
};

const FPS = 30;
const W = 1920;
const H = 1080;

const clips: Clip[] = [
  {
    src: "videos/000.mp4",
    seconds: 8.208333,
    title: "WHO",
    kicker: "Cracked Studio",
    layout: "wide",
    panel: "identity",
  },
  {
    src: "videos/001a.mp4",
    seconds: 5.833333,
    title: "WHO",
    kicker: "Market price, without trust",
    layout: "wide",
    panel: "identity",
  },
  {
    src: "videos/001b.mp4",
    seconds: 13.52,
    title: "THE PROBLEM",
    kicker: "Provably fair is not enough",
    layout: "portrait",
    panel: "problem",
  },
  {
    src: "videos/002a.mp4",
    seconds: 7.98,
    title: "WHAT IT IS",
    kicker: "The price is derived",
    layout: "portrait",
    panel: "app",
  },
  {
    src: "videos/002b.mp4",
    seconds: 11.01,
    title: "WHAT IT IS",
    kicker: "Same recipe, same price",
    layout: "portrait",
    panel: "app",
  },
  {
    src: "videos/003a.mp4",
    seconds: 8.87,
    title: "WHY",
    kicker: "Remove the party",
    layout: "portrait",
    panel: "proof",
  },
  {
    src: "videos/003b.mp4",
    seconds: 17.101667,
    title: "THE PROOF",
    kicker: "A one-unit lie lost its bond",
    layout: "portrait",
    panel: "proof",
  },
];

const clipFrames = clips.map((clip) => Math.round(clip.seconds * FPS));
const starts = clipFrames.reduce<number[]>((acc, duration, index) => {
  acc[index + 1] = (acc[index] ?? 0) + duration;
  return acc;
}, [0]);

export const FOUNDER_DEMO_DURATION_FRAMES = starts[starts.length - 1] ?? 0;

const GlobalGrid: React.FC = () => (
  <AbsoluteFill style={{ pointerEvents: "none" }}>
    <svg width={W} height={H}>
      {Array.from({ length: Math.floor(W / 120) + 1 }, (_, i) => (
        <line key={`v${i}`} x1={i * 120} y1={0} x2={i * 120} y2={H} stroke={RULE} strokeWidth={1} opacity={0.7} />
      ))}
      {Array.from({ length: Math.floor(H / 120) + 1 }, (_, i) => (
        <line key={`h${i}`} x1={0} y1={i * 120} x2={W} y2={i * 120} stroke={RULE} strokeWidth={1} opacity={0.7} />
      ))}
    </svg>
  </AbsoluteFill>
);

const FilmGrain: React.FC = () => (
  <AbsoluteFill style={{ opacity: 0.055, mixBlendMode: "screen", pointerEvents: "none" }}>
    <svg width={W} height={H}>
      <filter id="grain">
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" stitchTiles="stitch" />
      </filter>
      <rect width={W} height={H} filter="url(#grain)" />
    </svg>
  </AbsoluteFill>
);

const TopBar: React.FC = () => {
  const frame = useCurrentFrame();
  const totalSeconds = Math.floor(frame / FPS);
  return (
    <div
      style={{
        position: "absolute",
        left: 54,
        top: 38,
        right: 54,
        height: 64,
        borderBottom: `1px solid ${RULE}`,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        fontFamily: mono,
        fontSize: 18,
        letterSpacing: 4,
        color: DIM,
        textTransform: "uppercase",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
        <Img src={staticFile("brand/croom-logo-wide.png")} style={{ width: 150, height: "auto" }} />
        <span>Derived, not reported</span>
      </div>
      <span>{`00:${String(totalSeconds).padStart(2, "0")} / ${Math.round(FOUNDER_DEMO_DURATION_FRAMES / FPS)}s`}</span>
    </div>
  );
};

const CaptionLayer: React.FC = () => {
  const frame = useCurrentFrame();
  const now = (frame / FPS) * 1000;
  const caption = (CAPTIONS as Caption[]).find((candidate) => now >= candidate.startMs && now <= candidate.endMs);
  const enter = caption
    ? Math.min(
        1,
        interpolate(now - caption.startMs, [0, 280], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        }),
      )
    : 0;

  if (!caption) return null;

  return (
    <div
      style={{
        position: "absolute",
        left: 54,
        right: 54,
        bottom: 42,
        display: "grid",
        gridTemplateColumns: "210px 1fr",
        border: `1px solid ${RULE}`,
        background: "rgba(9,9,11,0.88)",
        opacity: enter,
      }}
    >
      <div
        style={{
          padding: "20px 22px",
          borderRight: `1px solid ${RULE}`,
          fontFamily: mono,
          fontSize: 16,
          color: ACCENT,
          letterSpacing: 4,
          textTransform: "uppercase",
        }}
      >
        Script
      </div>
      <div
        style={{
          padding: "18px 24px",
          fontFamily: display,
          fontSize: 36,
          lineHeight: 1.14,
          color: TEXT,
          letterSpacing: 0,
        }}
      >
        {caption.text}
      </div>
    </div>
  );
};

const Badge: React.FC<{ children: React.ReactNode; color?: string }> = ({ children, color = DIM }) => (
  <span
    style={{
      display: "inline-block",
      border: `1px solid ${color}`,
      color,
      padding: "8px 11px",
      fontFamily: mono,
      fontSize: 13,
      fontWeight: 700,
      letterSpacing: 3,
      textTransform: "uppercase",
    }}
  >
    {children}
  </span>
);

const LineChart: React.FC = () => {
  const frame = useCurrentFrame();
  const draw = interpolate(frame, [0, 72], [4200, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const points = POINTS as [number, number][];
  const path = points.map(([x, y], i) => `${i ? "L" : "M"}${80 + x * 610},${60 + y * 220}`).join("");
  return (
    <svg width={760} height={330} viewBox="0 0 760 330">
      <rect x={0} y={0} width={760} height={330} fill={INK} stroke={RULE} />
      {[0, 1, 2, 3].map((i) => (
        <line key={i} x1={52} y1={52 + i * 70} x2={708} y2={52 + i * 70} stroke={RULE} strokeDasharray="3 7" />
      ))}
      <path d={`${path}L690,286L80,286Z`} fill="rgba(139,124,255,0.15)" />
      <path
        d={path}
        fill="none"
        stroke={ACCENT}
        strokeWidth={5}
        strokeLinejoin="round"
        strokeLinecap="round"
        strokeDasharray={4200}
        strokeDashoffset={draw}
      />
    </svg>
  );
};

const IdentityPanel: React.FC = () => (
  <div style={{ display: "grid", gap: 20 }}>
    <Badge color={ACCENT}>Croom</Badge>
    <h1 style={{ margin: 0, fontFamily: display, fontSize: 74, lineHeight: 0.96, color: TEXT, textTransform: "uppercase" }}>
      Markets nobody can rig
    </h1>
    <p style={{ margin: 0, fontFamily: mono, fontSize: 22, lineHeight: 1.45, color: DIM }}>
      Public randomness in. Deterministic price out. No operator discretion in the middle.
    </p>
  </div>
);

const ProblemPanel: React.FC = () => (
  <div style={{ display: "grid", gap: 18 }}>
    <Badge color={BAD}>Problem</Badge>
    <h2 style={{ margin: 0, fontFamily: display, fontSize: 58, lineHeight: 1, color: TEXT, textTransform: "uppercase" }}>
      The house picks the seed
    </h2>
    {[
      ["Seed commitment", "proves no after-the-bet change"],
      ["Seed selection", "still chosen by whoever profits"],
      ["Synthetic price", "the number you lose to"],
    ].map(([label, value]) => (
      <div key={label} style={{ border: `1px solid ${RULE}`, padding: 18, background: "rgba(17,17,22,0.82)" }}>
        <div style={{ fontFamily: mono, fontSize: 13, color: DIM, letterSpacing: 3, textTransform: "uppercase" }}>{label}</div>
        <div style={{ marginTop: 10, fontFamily: display, fontSize: 31, color: TEXT, textTransform: "uppercase" }}>{value}</div>
      </div>
    ))}
  </div>
);

const AppPanel: React.FC = () => (
  <div style={{ display: "grid", gap: 20 }}>
    <Badge color={GOOD}>App</Badge>
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
      {[
        ["drand evmnet", "3s"],
        ["RPC while deriving", "0"],
        ["price source", "beacon"],
        ["tamper surface", "none"],
      ].map(([label, value]) => (
        <div key={label} style={{ border: `1px solid ${RULE}`, padding: 18, background: PANEL }}>
          <div style={{ fontFamily: mono, fontSize: 12, color: DIM, letterSpacing: 3, textTransform: "uppercase" }}>{label}</div>
          <div style={{ marginTop: 12, fontFamily: mono, fontSize: 42, color: value === "0" ? GOOD : TEXT, fontWeight: 700 }}>
            {value}
          </div>
        </div>
      ))}
    </div>
    <LineChart />
    <div style={{ fontFamily: mono, fontSize: 18, lineHeight: 1.55, color: DIM }}>
      Same room spec + same beacon rounds = identical prices, forever.
    </div>
  </div>
);

const ProofPanel: React.FC = () => {
  const frame = useCurrentFrame();
  const stamp = spring({ frame: frame - 24, fps: FPS, config: { damping: 18, stiffness: 160 } });
  return (
    <div style={{ display: "grid", gap: 20 }}>
      <Badge color={BAD}>Fraud proof</Badge>
      <h2 style={{ margin: 0, fontFamily: display, fontSize: 60, lineHeight: 0.98, color: TEXT, textTransform: "uppercase" }}>
        One wei of price was enough
      </h2>
      <div style={{ border: `1px solid ${RULE}`, padding: 20, background: PANEL }}>
        <div style={{ fontFamily: mono, fontSize: 13, color: DIM, letterSpacing: 3, textTransform: "uppercase" }}>
          false close
        </div>
        <div style={{ marginTop: 12, fontFamily: mono, fontSize: 34, color: BAD, fontWeight: 700 }}>
          99.999827000000000001
        </div>
      </div>
      <div style={{ transform: `scale(${interpolate(stamp, [0, 1], [1.12, 1])})`, transformOrigin: "left center" }}>
        <Badge color={BAD}>bond forfeited</Badge>
      </div>
      <div style={{ fontFamily: mono, fontSize: 18, lineHeight: 1.55, color: DIM }}>
        The chain catches the lie. The browser can reproduce the honest price.
      </div>
    </div>
  );
};

const SidePanel: React.FC<{ clip: Clip }> = ({ clip }) => {
  const panel = {
    identity: <IdentityPanel />,
    problem: <ProblemPanel />,
    app: <AppPanel />,
    proof: <ProofPanel />,
  }[clip.panel];

  return (
    <div
      style={{
        position: "absolute",
        left: 86,
        top: 154,
        width: 795,
        minHeight: 730,
        border: `1px solid ${RULE}`,
        background: "rgba(9,9,11,0.78)",
        padding: 34,
      }}
    >
      <div style={{ marginBottom: 26, fontFamily: mono, fontSize: 15, color: DIM, letterSpacing: 4, textTransform: "uppercase" }}>
        {clip.title} / {clip.kicker}
      </div>
      {panel}
    </div>
  );
};

const VideoScene: React.FC<{ clip: Clip }> = ({ clip }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200 }, durationInFrames: 14 });
  const src = staticFile(clip.src);

  if (clip.layout === "wide") {
    return (
      <AbsoluteFill style={{ backgroundColor: INK }}>
        <Video
          src={src}
          objectFit="cover"
          style={{ width: "100%", height: "100%", filter: "brightness(0.72)" }}
        />
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(90deg, rgba(9,9,11,.9), rgba(9,9,11,.18) 58%, rgba(9,9,11,.45))" }} />
        <div
          style={{
            position: "absolute",
            left: 86,
            top: 186,
            width: 740,
            opacity: enter,
            transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px)`,
          }}
        >
          <IdentityPanel />
        </div>
      </AbsoluteFill>
    );
  }

  return (
    <AbsoluteFill style={{ backgroundColor: INK }}>
      <Video
        src={src}
        muted
        objectFit="cover"
        style={{
          width: "100%",
          height: "100%",
          filter: "blur(32px) brightness(0.28) saturate(0.85)",
          transform: "scale(1.08)",
        }}
      />
      <GlobalGrid />
      <SidePanel clip={clip} />
      <div
        style={{
          position: "absolute",
          right: 116,
          top: 132,
          width: 640,
          height: 852,
          border: `1px solid ${RULE}`,
          background: PANEL,
          padding: 12,
          opacity: enter,
          transform: `translateX(${interpolate(enter, [0, 1], [34, 0])}px)`,
        }}
      >
        <Video src={src} objectFit="contain" style={{ width: "100%", height: "100%", backgroundColor: INK }} />
      </div>
    </AbsoluteFill>
  );
};

export const FounderDemo: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: INK }}>
    {clips.map((clip, index) => (
      <Sequence key={clip.src} from={starts[index]} durationInFrames={clipFrames[index]} premountFor={15}>
        <VideoScene clip={clip} />
      </Sequence>
    ))}
    <GlobalGrid />
    <TopBar />
    <CaptionLayer />
    <FilmGrain />
  </AbsoluteFill>
);
