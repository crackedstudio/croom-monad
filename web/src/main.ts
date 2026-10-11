/**
 * Croom on Monad — a page that derives a Room's chart from the drand beacon and then asks the
 * chain whether it agrees.
 *
 * The ordering matters and is the whole argument. The chart is computed first, locally, from
 * public randomness, using the same frozen specification the contracts implement. Monad is
 * consulted afterwards, to compare commitments. If the chain were unreachable the chart would
 * still be right, and the page says so by counting its own RPC calls.
 */
import {
  addresses,
  addressUrl,
  RPC_URLS,
  checkpoint,
  connect,
  marketAbi,
  provenFloor,
  publicClient,
  roomsOpened,
  txUrl,
} from "./chain.js";
import { DEPLOYMENTS, EXPLORER } from "./deployments.js";
import {
  decodeSpec,
  deriveEpoch,
  deriveSeries,
  DrandClient,
  EVMNET,
  Family,
  epochOf,
  epochRange,
  roomId as computeRoomId,
  WAD,
  type Candle,
  type RoomSpec,
} from "./protocol.js";

// ── proving the claim: count every request to Monad ──────────────────────────────────────────
//
// "No RPC" is easy to assert and easy to get wrong, so the page instruments itself. Any fetch to
// the Monad endpoint increments a counter shown on screen. Deriving the chart must leave it at
// zero; only the verification step is allowed to move it.
let rpcCalls = 0;
/** Snapshot taken when a derivation starts, so the badge reports that derivation's calls. */
let rpcAtDeriveStart = 0;
/**
 * The badge stops updating once derivation finishes. Verification afterwards *does* query Monad —
 * that is its job — and letting those calls land in a counter labelled "while deriving" would
 * misstate the very claim the counter exists to support.
 */
let countingDerivation = false;
const realFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  // Every endpoint, not just the primary: with a fallback transport, counting only one would let
  // the badge read zero because the chain was being reached some other way.
  if (RPC_URLS.some((candidate) => url.startsWith(candidate))) {
    rpcCalls += 1;
    queueMicrotask(renderRpcCounter);
  }
  return realFetch(input as never, init);
}) as typeof fetch;

const hex = (b: Uint8Array) => "0x" + [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
const short = (s: string, n = 10) => `${s.slice(0, 2 + n)}…${s.slice(-6)}`;

/** WAD to a human string. Integer-only: never a float, for the same reason the protocol is not. */
function fmt(v: bigint, decimals = 4): string {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const whole = a / WAD;
  const frac = (a % WAD).toString().padStart(18, "0").slice(0, decimals);
  return `${neg ? "-" : ""}${whole.toLocaleString("en-US")}${decimals ? "." + frac : ""}`;
}

const el = (html: string): HTMLElement => {
  const d = document.createElement("div");
  d.innerHTML = html.trim();
  return d.firstElementChild as HTMLElement;
};

const app = document.getElementById("app")!;
const drand = new DrandClient();

interface Room {
  roomId: string;
  creator: string;
  spec: RoomSpec;
}

const state: {
  rooms: Room[];
  selected?: Room;
  series?: Candle[];
  floor?: bigint;
  beaconHead?: bigint;
} = { rooms: [] };

function renderRpcCounter() {
  const node = document.getElementById("rpc-count");
  if (node) {
    if (!countingDerivation && node.dataset.frozen === "1") return;
    const made = rpcCalls - rpcAtDeriveStart;
    node.textContent = String(made);
    node.className = made === 0 ? "badge good" : "badge bad";
  }
}

// ── the chart ────────────────────────────────────────────────────────────────────────────────

function chartSvg(candles: Candle[]): string {
  if (candles.length === 0) return `<p class="note">No rounds yet.</p>`;

  const W = 1000;
  const H = 320;
  const pad = { l: 8, r: 64, t: 12, b: 24 };

  let lo = candles[0]!.low;
  let hi = candles[0]!.high;
  for (const c of candles) {
    if (c.low < lo) lo = c.low;
    if (c.high > hi) hi = c.high;
  }
  const span = hi - lo === 0n ? 1n : hi - lo;

  const x = (i: number) => pad.l + ((W - pad.l - pad.r) * i) / Math.max(1, candles.length - 1);
  // Integer arithmetic down to the last moment: only the pixel is allowed to be a float.
  const y = (v: bigint) =>
    pad.t + (H - pad.t - pad.b) * (1 - Number(((v - lo) * 10_000n) / span) / 10_000);

  const line = candles.map((c, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(c.close).toFixed(1)}`).join("");
  const area = `${line}L${x(candles.length - 1).toFixed(1)},${H - pad.b}L${x(0).toFixed(1)},${H - pad.b}Z`;

  const first = candles[0]!.close;
  const last = candles[candles.length - 1]!.close;
  const up = last >= first;
  const stroke = up ? "#56d364" : "#f85149";

  const ticks = [lo, lo + span / 2n, hi]
    .map(
      (v) =>
        `<text x="${W - pad.r + 8}" y="${(y(v) + 4).toFixed(1)}" fill="#8b949e" font-size="11" font-family="ui-monospace,monospace">${fmt(v, 2)}</text>
         <line x1="${pad.l}" y1="${y(v).toFixed(1)}" x2="${W - pad.r}" y2="${y(v).toFixed(1)}" stroke="#222932" stroke-dasharray="2 4"/>`,
    )
    .join("");

  return `
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Room price chart derived from the beacon">
      <defs>
        <linearGradient id="fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="${stroke}" stop-opacity="0.22"/>
          <stop offset="1" stop-color="${stroke}" stop-opacity="0"/>
        </linearGradient>
      </defs>
      ${ticks}
      <path d="${area}" fill="url(#fill)"/>
      <path d="${line}" fill="none" stroke="${stroke}" stroke-width="1.75"/>
    </svg>`;
}

// ── panels ───────────────────────────────────────────────────────────────────────────────────

function beaconPanel(): string {
  const floor = state.floor ?? 0n;
  const head = state.beaconHead ?? 0n;
  const behind = head > floor ? head - floor : 0n;
  const hours = Number(behind * 3n) / 3600;
  const stale = behind > 1200n; // more than an hour of beacon time

  return `
  <div class="row">
    <div class="panel">
      <div class="label">drand evmnet head</div>
      <div class="big">${head.toLocaleString("en-US")}</div>
      <div class="note">A signed random value every 3 seconds, from the League of Entropy.</div>
    </div>
    <div class="panel">
      <div class="label">proven floor on Monad</div>
      <div class="big">${floor.toLocaleString("en-US")}</div>
      <div class="note">
        The highest round <em>proved</em> to exist on chain.
        <a href="${addressUrl(addresses.entropy)}" target="_blank" rel="noreferrer">Entropy</a>
      </div>
    </div>
    <div class="panel">
      <div class="label">floor staleness</div>
      <div class="big">${behind.toLocaleString("en-US")}</div>
      <div style="margin-top:6px">
        <span class="badge ${stale ? "warn" : "good"}">${hours < 1 ? `${(hours * 60).toFixed(0)} min` : `${hours.toFixed(1)} hours`} behind</span>
      </div>
      <div class="note">
        ${
          stale
            ? `A stale floor <strong>weakens</strong> the fairness rule rather than tightening it:
               both the Room-creation and market-entry checks compare against the floor, so a low
               floor admits rounds that are already public. We report this as a finding against the
               specification, which says the opposite.`
            : `Fresh enough for the fairness rules to bind.`
        }
      </div>
    </div>
  </div>`;
}

function specTable(room: Room): string {
  const s = room.spec;
  const family = Family[s.params.family] ?? String(s.params.family);
  const param = "sigma" in s.params ? (s.params as { sigma: bigint }).sigma : (s.params as { step: bigint }).step;
  const paramLabel = "sigma" in s.params ? "volatility (annual)" : "step size";
  const paramValue = "sigma" in s.params ? `${fmt(param * 100n, 2)}%` : fmt(param);

  return `
  <table>
    <tr><td>room id</td><td>${short(room.roomId, 14)}</td></tr>
    <tr><td>family</td><td>${family}</td></tr>
    <tr><td>${paramLabel}</td><td>${paramValue}</td></tr>
    <tr><td>opening price</td><td>${fmt(s.initialPrice, 2)}</td></tr>
    <tr><td>sub-ticks per round</td><td>${s.subTicks}</td></tr>
    <tr><td>rounds per epoch</td><td>${s.epochRounds}</td></tr>
    <tr><td>first round</td><td>${s.genesisRound.toLocaleString("en-US")}</td></tr>
    <tr><td>creator</td><td><a href="${addressUrl(room.creator)}" target="_blank" rel="noreferrer">${short(room.creator, 8)}</a></td></tr>
  </table>
  <div class="note">
    Every field is hashed into the room id, so none of them can change. A different parameter is a
    different Room, not an edited one.
  </div>`;
}

async function verifyPanel(room: Room): Promise<string> {
  const candles = state.series ?? [];
  if (candles.length === 0) return "";

  const lastRound = candles[candles.length - 1]!.round;
  const lastComplete = epochOf(room.spec, lastRound);

  // Look for an epoch somebody has actually committed to, rather than defaulting to the most
  // recent one. A page that only ever reports "no checkpoint posted" demonstrates nothing, and the
  // interesting epochs are the early ones a poster has reached.
  let target: bigint | null = null;
  let onChain: Awaited<ReturnType<typeof checkpoint>> = null;
  for (let e = 0n; e <= lastComplete && e < 12n; e++) {
    const found = await checkpoint(room.roomId as `0x${string}`, e);
    if (found) {
      target = e;
      onChain = found;
      break;
    }
  }

  if (target === null || !onChain) {
    return `
    <div class="panel">
      <div class="label">verify against chain</div>
      <span class="badge dim">no checkpoint posted yet</span>
      <div class="note">
        Nobody has committed an epoch for this Room. The prices above are still correct &mdash; the
        chain's silence says nothing about them. That is the point of deriving rather than being
        told: an absent commitment is a bookkeeping gap, not an absence of truth.
      </div>
    </div>`;
  }

  const [r0, r1] = epochRange(room.spec, target);
  const local = await deriveEpoch(room.spec, target, drand);
  const localRoot = hex(local.path.merkleRoot);
  const agree = localRoot.toLowerCase() === onChain.merkleRoot.toLowerCase();

  const verdict = agree
    ? `<div class="note">The root computed in this browser matches the one committed on Monad.
       Nothing was taken on trust: the beacon is public, and the derivation is the same frozen
       specification the contract implements.</div>`
    : `<div class="note">
         <strong>The committed root is not the one the beacon produces.</strong> Whoever posted it
         was wrong, and anyone who noticed could take their bond &mdash; with no stake of their own,
         because the proof is one shot rather than a game.
         ${onChain.status === "Rejected" ? " Somebody did: this checkpoint has been <strong>rejected</strong> and the bond forfeited." : ""}
       </div>`;

  return `
  <div class="panel">
    <div class="label">verify against chain &mdash; epoch ${target} (rounds ${r0.toLocaleString("en-US")}&ndash;${r1.toLocaleString("en-US")})</div>
    <div style="margin-bottom:10px">
      <span class="badge ${agree ? "good" : "bad"}">${agree ? "commitments agree" : "commitments disagree"}</span>
      <span class="badge ${onChain.status === "Final" ? "good" : onChain.status === "Rejected" ? "bad" : "warn"}">${onChain.status.toLowerCase()}</span>
    </div>
    <table>
      <tr><td>computed in this browser</td><td>${short(localRoot, 14)}</td></tr>
      <tr><td>committed on Monad</td><td>${short(onChain.merkleRoot, 14)}</td></tr>
      <tr><td>posted by</td><td><a href="${addressUrl(onChain.poster)}" target="_blank" rel="noreferrer">${short(onChain.poster, 8)}</a></td></tr>
      <tr><td>bond still held</td><td>${fmt(onChain.bond, 3)} MON</td></tr>
    </table>
    ${verdict}
  </div>`;
}

// ── boot ─────────────────────────────────────────────────────────────────────────────────────

function shell(body: string): void {
  app.innerHTML = `
    ${beaconPanel()}
    <div class="panel">
      <div class="controls">
        <select id="room"></select>
        <button id="load" class="primary">Derive chart</button>
        <span class="note" style="margin:0">
          RPC calls to Monad while deriving:
          <span id="rpc-count" class="badge good">0</span>
        </span>
      </div>
      <div id="chart"></div>
    </div>
    ${body}`;

  const select = document.getElementById("room") as HTMLSelectElement;
  select.innerHTML = state.rooms
    .map((r, i) => {
      const fam = Family[r.spec.params.family] ?? r.spec.params.family;
      const p = "sigma" in r.spec.params ? `${fmt((r.spec.params as { sigma: bigint }).sigma * 100n, 0)}% vol` : "step";
      return `<option value="${i}"${state.selected === r ? " selected" : ""}>${fam} · ${p} · ${short(r.roomId, 6)}</option>`;
    })
    .join("");

  document.getElementById("load")!.addEventListener("click", () => {
    state.selected = state.rooms[Number(select.value)];
    void loadChart();
  });
  renderRpcCounter();
}

async function loadChart(): Promise<void> {
  const room = state.selected;
  if (!room) return;

  const chart = document.getElementById("chart")!;
  rpcAtDeriveStart = rpcCalls;
  countingDerivation = true;
  const before = rpcCalls;
  renderRpcCounter();

  // Deliberately bounded so a demo stays quick; the derivation itself has no limit.
  const span = 240n;
  const to = room.spec.genesisRound + span - 1n;

  chart.innerHTML = `<p class="note">Fetching and verifying ${span} beacon rounds, then deriving…</p>`;
  try {
    const series = await deriveSeries(room.spec, to, drand, (done, total) => {
      chart.innerHTML = `<p class="note">Verified and derived ${done} of ${total} rounds…</p>`;
    });
    state.series = series.candles;
    countingDerivation = false;
    const node = document.getElementById("rpc-count");
    if (node) node.dataset.frozen = "1";

    const derivedId = hex(computeRoomId(room.spec));
    const idOk = derivedId.toLowerCase() === room.roomId.toLowerCase();

    chart.innerHTML = `
      ${chartSvg(series.candles)}
      <div class="note" style="margin-top:12px">
        <span class="badge ${rpcCalls === before ? "good" : "bad"}">
          ${rpcCalls === before ? "zero RPC calls" : `${rpcCalls - before} RPC calls`}
        </span>
        ${series.candles.length} rounds derived in this browser from the public beacon.
        Room id recomputed from the spec: <span class="badge ${idOk ? "good" : "bad"}">${idOk ? "matches" : "mismatch"}</span>
      </div>`;

    app.insertAdjacentHTML("beforeend", "");
    const extra = await verifyPanel(room);
    const panels = document.getElementById("panels");
    if (panels) panels.innerHTML = specTable(room) ? `${extra}` : extra;
  } catch (err) {
    chart.innerHTML = `<p class="note" style="color:var(--bad)">${(err as Error).message}</p>`;
  }
}

async function main(): Promise<void> {
  app.innerHTML = `<div class="panel"><p class="note">Reading the beacon and the chain…</p></div>`;

  const [head, floor, opened] = await Promise.all([
    drand.round("latest").then((r) => r.round),
    provenFloor(),
    roomsOpened(),
  ]);

  state.beaconHead = head;
  state.floor = floor;
  state.rooms = opened.flatMap((o) => {
    try {
      const bytes = Uint8Array.from(
        (o.spec.slice(2).match(/.{2}/g) ?? []).map((b) => parseInt(b, 16)),
      );
      return [{ roomId: o.roomId, creator: o.creator, spec: decodeSpec(bytes) }];
    } catch {
      return [];
    }
  });
  state.selected = state.rooms[0];

  shell(`
    <div class="row">
      <div class="panel">
        <div class="label">this Room's spec</div>
        <div id="spec">${state.selected ? specTable(state.selected) : ""}</div>
      </div>
      <div class="panel">
        <div class="label">deployed on Monad testnet</div>
        <table>
          ${Object.entries(DEPLOYMENTS)
            .filter(([n]) => ["Entropy", "Registry", "Ladder", "Market"].includes(n))
            .map(
              ([n, d]) =>
                `<tr><td>${n}</td><td><a href="${EXPLORER}/address/${d.address}" target="_blank" rel="noreferrer">${short(d.address, 8)}</a></td></tr>`,
            )
            .join("")}
          <tr><td>beacon</td><td>${EVMNET.scheme}</td></tr>
          <tr><td>rooms open</td><td>${state.rooms.length}</td></tr>
        </table>
      </div>
    </div>
    <div id="panels"></div>`);

  if (state.selected) await loadChart();
}

void main().catch((err) => {
  app.innerHTML = `<div class="panel"><p class="note" style="color:var(--bad)">${(err as Error).message}</p></div>`;
});
