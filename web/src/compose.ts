/**
 * "Open your own Room" — where content-addressing becomes obvious instead of abstract.
 *
 * The room id is the hash of the specification, so the interesting thing is not the chart: it is
 * that the id changes the instant you move a slider. There is no version of a Room with different
 * parameters. There is only a different Room. That is why nobody can edit one, including whoever
 * opened it, and it is much easier to see than to read.
 *
 * Only Drift and Step are offered, because those are the two families the deployed contract
 * compiles — `Tick.compile` reverts with `UnsupportedFamily` on anything else (src/Tick.sol:75).
 * Offering a family the chain cannot derive would make the panel a mockup, and the whole point of
 * this page is that nothing on it is a mockup.
 */
import {
  deriveRound,
  encodeSpec,
  Family,
  Model,
  roomId as computeRoomId,
  WAD,
  type Candle,
  type RoomSpec,
} from "./protocol.js";
import type { beacon } from "./beacon.js";

type Drand = typeof beacon;

const hex = (b: Uint8Array) => "0x" + [...b].map((x) => x.toString(16).padStart(2, "0")).join("");

/** Rounds drawn in the preview. Past rounds, and the panel says so. */
const PREVIEW = 120n;

interface Draft {
  family: Family.Drift | Family.Step;
  /** Annualised volatility in percent, for Drift. */
  volPct: number;
  /** Absolute step per sub-tick in hundredths, for Step. */
  stepCents: number;
  subTicks: number;
}

const draft: Draft = { family: Family.Drift, volPct: 75, stepCents: 25, subTicks: 1 };

function fmt(v: bigint, decimals = 2): string {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const whole = a / WAD;
  const frac = (a % WAD).toString().padStart(18, "0").slice(0, decimals);
  return `${neg ? "-" : ""}${whole.toLocaleString("en-US")}${decimals ? "." + frac : ""}`;
}

/** The draft as a real spec. `genesisRound` is supplied by the caller, because it is the one field
 * the protocol will not let you choose freely. */
export function draftSpec(genesisRound: bigint): RoomSpec {
  return {
    beacon: 0,
    subTicks: draft.subTicks,
    epochRounds: 20,
    genesisRound,
    initialPrice: 100n * WAD,
    decimals: 2,
    mathVersion: 1,
    hashFn: 1,
    params:
      draft.family === Family.Drift
        ? { family: Family.Drift, sigma: (BigInt(draft.volPct) * WAD) / 100n }
        : { family: Family.Step, step: (BigInt(draft.stepCents) * WAD) / 100n },
  };
}

function preview(candles: Candle[]): string {
  if (candles.length < 2) return `<p class="note">Deriving…</p>`;
  const W = 1000;
  const H = 150;
  let lo = candles[0]!.low;
  let hi = candles[0]!.high;
  for (const c of candles) {
    if (c.low < lo) lo = c.low;
    if (c.high > hi) hi = c.high;
  }
  const span = hi - lo === 0n ? 1n : hi - lo;
  const x = (i: number) => 8 + ((W - 72) * i) / (candles.length - 1);
  const y = (v: bigint) => 12 + (H - 34) * (1 - Number(((v - lo) * 10_000n) / span) / 10_000);
  const line = candles.map((c, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(c.close).toFixed(1)}`).join("");

  return `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto" role="img"
      aria-label="Preview of the Room you have specified">
    <text x="${W - 64}" y="${(y(hi) + 4).toFixed(1)}" fill="var(--dimmer)" font-size="11" font-family="ui-monospace,monospace">${fmt(hi)}</text>
    <text x="${W - 64}" y="${(y(lo) + 4).toFixed(1)}" fill="var(--dimmer)" font-size="11" font-family="ui-monospace,monospace">${fmt(lo)}</text>
    <path d="${line}" fill="none" stroke="var(--accent)" stroke-width="1.75"/>
  </svg>`;
}

/** Derives the preview locally. No network beyond the beacon rounds already in hand. */
function derivePreview(spec: RoomSpec, rounds: [bigint, Uint8Array][]): Candle[] {
  const model = new Model(spec, computeRoomId(spec));
  let state = model.initialState();
  const out: Candle[] = [];
  for (const [round, rand] of rounds) {
    const res = deriveRound(model, state, round, rand);
    state = res.state;
    out.push({ round, close: res.leaf.close, high: res.leaf.high, low: res.leaf.low });
  }
  return out;
}

export interface ComposeOptions {
  /** The proven floor, so the fairness rule can be stated with a real number. */
  floor: bigint;
  /** Hands the current draft to the prediction game. */
  onUse: (spec: RoomSpec) => void;
}

export async function mountCompose(
  host: HTMLElement,
  drand: Drand,
  opts: ComposeOptions,
): Promise<void> {
  host.innerHTML = `<div class="label">open your own room</div>
    <p class="note">Fetching beacon rounds for the preview…</p>`;

  const head = (await drand.round("latest")).round;
  const from = head - PREVIEW + 1n;
  const rounds = await drand.verifiedRandomness(from, head);

  const render = () => {
    const spec = draftSpec(from);
    const id = hex(computeRoomId(spec));
    const bytes = encodeSpec(spec);
    const candles = derivePreview(spec, rounds);
    const isDrift = draft.family === Family.Drift;

    host.innerHTML = `
      <div class="label">open your own room</div>
      <p class="note" style="margin:0 0 14px">
        Pick the parameters. The room id underneath is the hash of exactly these fields, so it
        changes the moment you move anything &mdash; there is no such thing as editing a Room, only
        a different one.
      </p>

      <div class="controls" style="margin:0 0 4px">
        <button id="fam-drift" class="${isDrift ? "primary" : ""}">Drift</button>
        <button id="fam-step" class="${isDrift ? "" : "primary"}">Step</button>
        <span class="note" style="margin:0">
          ${
            isDrift
              ? `Geometric Brownian motion &mdash; the shape most people picture when they picture a chart.`
              : `A coin flip each sub-tick, a fixed amount either way, floored so it can never reach zero.`
          }
        </span>
      </div>

      <div class="controls" style="margin:14px 0 0">
        ${
          isDrift
            ? `<label class="label" style="margin:0;min-width:160px">volatility ${draft.volPct}% / year</label>
               <input id="vol" type="range" min="10" max="300" step="5" value="${draft.volPct}" style="flex:1;min-width:200px" />`
            : `<label class="label" style="margin:0;min-width:160px">step ${fmt((BigInt(draft.stepCents) * WAD) / 100n)}</label>
               <input id="step" type="range" min="1" max="200" step="1" value="${draft.stepCents}" style="flex:1;min-width:200px" />`
        }
      </div>
      <div class="controls" style="margin:12px 0 16px">
        <label class="label" style="margin:0;min-width:160px">sub-ticks per round ${draft.subTicks}</label>
        <input id="sub" type="range" min="1" max="8" step="1" value="${draft.subTicks}" style="flex:1;min-width:200px" />
      </div>

      ${preview(candles)}

      <table style="margin-top:14px">
        <tr><td>room id</td><td style="color:var(--accent)">${id.slice(0, 26)}…${id.slice(-6)}</td></tr>
        <tr><td>canonical spec</td><td>${bytes.length} bytes</td></tr>
        <tr><td>opening price</td><td>${fmt(spec.initialPrice)}</td></tr>
      </table>

      <p class="note" style="margin:14px 0 0">
        The chart above is drawn from <strong>past</strong> beacon rounds, so you can see what the
        parameters do. A Room you actually opened could not start there: the Registry requires its
        first round to sit above the proven floor, currently
        <strong>${opts.floor.toLocaleString("en-US")}</strong>. That rule is the reason nobody can
        shop for a Room whose outcome they have already seen &mdash; including you, right now.
      </p>
      <div class="controls" style="margin:16px 0 0">
        <button id="use" class="primary">Play this Room above</button>
        <span class="note" style="margin:0">Takes these parameters into the prediction game, starting at the live head.</span>
      </div>`;

    const on = (id: string, ev: string, fn: (e: Event) => void) =>
      host.querySelector(`#${id}`)?.addEventListener(ev, fn);

    on("fam-drift", "click", () => {
      draft.family = Family.Drift;
      render();
    });
    on("fam-step", "click", () => {
      draft.family = Family.Step;
      render();
    });
    on("vol", "input", (e) => {
      draft.volPct = Number((e.target as HTMLInputElement).value);
      render();
    });
    on("step", "input", (e) => {
      draft.stepCents = Number((e.target as HTMLInputElement).value);
      render();
    });
    on("sub", "input", (e) => {
      draft.subTicks = Number((e.target as HTMLInputElement).value);
      render();
    });
    on("use", "click", () => opts.onUse(draftSpec(from)));
  };

  render();
}
