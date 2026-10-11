/**
 * "Call the next tick" — the trader's seat, where unpredictability stops being a claim.
 *
 * A visitor can read "nobody can predict it" and nod. What they cannot argue with is their own
 * hit rate sitting on 50% after twenty guesses, however carefully they chose.
 *
 * The integrity of the game is the one thing worth being strict about: a guess is only accepted
 * for a round the beacon has **not yet published**. If this tab has fallen behind — backgrounded,
 * throttled, a slow mirror — the round after the last one drawn may already be public, and
 * accepting a guess on it would make the whole panel a lie. So the guess catches up to the live
 * head first and then takes the round after that.
 *
 * Nothing here touches Monad. The beacon is the only source, which is the point.
 */
import {
  deriveRound,
  Model,
  roomId as computeRoomId,
  type Candle,
  type RoomSpec,
  type State,
} from "./protocol.js";
import type { beacon } from "./beacon.js";

type Drand = typeof beacon;

/** How many past rounds to draw so the panel opens with a chart rather than an empty box. */
const BACKFILL = 40n;
const POLL_MS = 1500;

interface Game {
  spec: RoomSpec;
  model: Model;
  state: State;
  candles: Candle[];
  last: bigint;
  /** A guess in flight: the round it is about, and which way. */
  pending?: { round: bigint; up: boolean; from: bigint };
  wins: number;
  played: number;
  /** Most recent outcome, for the banner. */
  last_result?: { won: boolean; up: boolean; from: bigint; to: bigint; round: bigint };
  timer?: number;
  busy: boolean;
}

let game: Game | null = null;

function fmt(v: bigint, decimals = 2): string {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const whole = a / 10n ** 18n;
  const frac = (a % 10n ** 18n).toString().padStart(18, "0").slice(0, decimals);
  return `${neg ? "-" : ""}${whole.toLocaleString("en-US")}${decimals ? "." + frac : ""}`;
}

function spark(candles: Candle[], pendingFrom?: bigint): string {
  const show = candles.slice(-60);
  if (show.length < 2) return `<p class="note">Waiting for the beacon…</p>`;

  const W = 1000;
  const H = 170;
  let lo = show[0]!.close;
  let hi = show[0]!.close;
  for (const c of show) {
    if (c.close < lo) lo = c.close;
    if (c.close > hi) hi = c.close;
  }
  const span = hi - lo === 0n ? 1n : hi - lo;
  const x = (i: number) => 8 + ((W - 72) * i) / (show.length - 1);
  const y = (v: bigint) => 14 + (H - 40) * (1 - Number(((v - lo) * 10_000n) / span) / 10_000);

  const line = show.map((c, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(c.close).toFixed(1)}`).join("");
  const lastX = x(show.length - 1);
  const lastY = y(show[show.length - 1]!.close);
  const up = show[show.length - 1]!.close >= show[0]!.close;

  // While a guess is in flight, the level it will be judged against is drawn across the panel.
  const marker =
    pendingFrom === undefined
      ? ""
      : `<line x1="8" y1="${y(pendingFrom).toFixed(1)}" x2="${W - 64}" y2="${y(pendingFrom).toFixed(1)}"
           stroke="var(--accent)" stroke-width="1" stroke-dasharray="3 4"/>
         <text x="${W - 58}" y="${(y(pendingFrom) + 4).toFixed(1)}" fill="var(--accent)" font-size="11"
           font-family="ui-monospace,monospace">${fmt(pendingFrom)}</text>`;

  return `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto" role="img"
      aria-label="Your Room, advancing live with the beacon">
    ${marker}
    <path d="${line}" fill="none" stroke="${up ? "var(--good)" : "var(--bad)"}" stroke-width="1.75"/>
    <circle cx="${lastX.toFixed(1)}" cy="${lastY.toFixed(1)}" r="4" fill="var(--text)"/>
  </svg>`;
}

function scoreLine(g: Game): string {
  if (g.played === 0) {
    return `<span class="note" style="margin:0">No guesses yet. Twenty is enough to see the shape of it.</span>`;
  }
  const pct = (g.wins * 100) / g.played;
  const off = Math.abs(pct - 50);
  return `
    <span class="badge ${off < 15 ? "dim" : pct > 50 ? "good" : "bad"}">${g.wins} / ${g.played} &mdash; ${pct.toFixed(0)}%</span>
    <span class="note" style="margin:0">
      ${
        g.played < 8
          ? `Too few to mean anything yet; a coin does this too.`
          : off < 12
            ? `Converging on 50%, which is the claim. No reading of the chart moves it, because the next value is a BLS signature nobody has produced yet.`
            : `Still ${pct > 50 ? "above" : "below"} 50% after ${g.played}. Keep going &mdash; this is what a fair coin looks like over a short run.`
      }
    </span>`;
}

function render(host: HTMLElement): void {
  const g = game;
  if (!g) return;

  const waiting = g.pending !== undefined;
  const r = g.last_result;

  host.innerHTML = `
    <div class="label">call the next tick</div>
    <p class="note" style="margin:0 0 4px">
      This is your own Room, advancing live. Every three seconds the beacon signs a value and one
      more price appears. Say which way the next one goes &mdash; the round you are guessing on has
      not been published yet, and this panel will not let you guess on one that has.
    </p>
    ${spark(g.candles, g.pending?.from)}
    <div class="controls" style="margin:14px 0 10px">
      <button id="guess-up" ${waiting ? "disabled" : ""}>▲ Up</button>
      <button id="guess-down" ${waiting ? "disabled" : ""}>▼ Down</button>
      <span class="note" style="margin:0">
        ${
          waiting
            ? `Guessed <strong>${g.pending!.up ? "up" : "down"}</strong> on round
               <strong>${g.pending!.round.toLocaleString("en-US")}</strong>, which does not exist yet.
               Waiting for the League of Entropy to sign it…`
            : `round ${g.last.toLocaleString("en-US")} &middot; ${fmt(g.candles[g.candles.length - 1]?.close ?? 0n)}`
        }
      </span>
    </div>
    ${
      r
        ? `<div style="margin:0 0 12px">
             <span class="badge ${r.won ? "good" : "bad"}">${r.won ? "right" : "wrong"}</span>
             <span class="note" style="margin:0">
               round ${r.round.toLocaleString("en-US")} closed
               <strong>${fmt(r.to, 6)}</strong> against <strong>${fmt(r.from, 6)}</strong> &mdash;
               it went ${r.to >= r.from ? "up" : "down"}, you said ${r.up ? "up" : "down"}.
               ${
                 fmt(r.to) === fmt(r.from)
                   ? `<em>The move is smaller than two decimals would show, which is why six are
                      printed here: the comparison is exact, on integers, all eighteen digits.</em>`
                   : ""
               }
             </span>
           </div>`
        : ""
    }
    <div class="controls" style="margin:0">${scoreLine(g)}</div>`;

  host.querySelector("#guess-up")?.addEventListener("click", () => void guess(host, true));
  host.querySelector("#guess-down")?.addEventListener("click", () => void guess(host, false));
}

/** Advances the Room to `to`, deriving every round in between. */
async function advance(g: Game, to: bigint, drand: Drand): Promise<void> {
  if (to <= g.last) return;
  const rounds = await drand.verifiedRandomness(g.last + 1n, to);
  for (const [round, rand] of rounds) {
    const res = deriveRound(g.model, g.state, round, rand);
    g.state = res.state;
    g.candles.push({ round, close: res.leaf.close, high: res.leaf.high, low: res.leaf.low });
    g.last = round;

    if (g.pending && round === g.pending.round) {
      const went_up = res.leaf.close >= g.pending.from;
      const won = went_up === g.pending.up;
      g.played += 1;
      if (won) g.wins += 1;
      g.last_result = { won, up: g.pending.up, from: g.pending.from, to: res.leaf.close, round };
      g.pending = undefined;
    }
  }
}

async function guess(host: HTMLElement, up: boolean): Promise<void> {
  const g = game;
  if (!g || g.pending || g.busy) return;
  g.busy = true;
  try {
    // Catch up first. If this tab has been throttled, the round after our last one is already
    // public, and a guess on a published round would be worthless.
    const head = (await beaconOf().round("latest")).round;
    if (head > g.last) await advance(g, head, beaconOf());

    g.pending = {
      round: g.last + 1n,
      up,
      from: g.candles[g.candles.length - 1]!.close,
    };
    g.last_result = undefined;
  } finally {
    g.busy = false;
  }
  render(host);
}

// The client is injected at mount so this module stays testable, but the guess handler needs it
// too; keeping one reference is simpler than threading it through every listener.
let injected: Drand | null = null;
const beaconOf = (): Drand => injected!;

function tick(host: HTMLElement): void {
  const g = game;
  if (!g) return;
  g.timer = window.setTimeout(async () => {
    if (game === g && !g.busy) {
      g.busy = true;
      try {
        const head = (await beaconOf().round("latest")).round;
        if (head > g.last) {
          await advance(g, head, beaconOf());
          render(host);
        }
      } catch {
        // A mirror hiccup is not worth interrupting the panel for; the next tick retries.
      } finally {
        g.busy = false;
      }
    }
    tick(host);
  }, POLL_MS);
}

/** Starts, or restarts, the game on `spec` — rebased so its rounds are the live ones. */
export async function mountPredict(host: HTMLElement, spec: RoomSpec, drand: Drand): Promise<void> {
  injected = drand;
  if (game?.timer) window.clearTimeout(game.timer);

  host.innerHTML = `<div class="label">call the next tick</div>
    <p class="note">Deriving the last ${BACKFILL} rounds…</p>`;

  const head = (await drand.round("latest")).round;
  const rebased: RoomSpec = { ...spec, genesisRound: head - BACKFILL + 1n };
  const model = new Model(rebased, computeRoomId(rebased));

  game = {
    spec: rebased,
    model,
    state: model.initialState(),
    candles: [],
    last: rebased.genesisRound - 1n,
    wins: 0,
    played: 0,
    busy: false,
  };
  await advance(game, head, drand);
  render(host);
  tick(host);
}
