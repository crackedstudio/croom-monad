/**
 * "Try to rig it" — hand the visitor the attacker's seat.
 *
 * The concept Croom actually turns on is that nobody can move a price, including the people who
 * built it. That is a claim, and a claim invites nodding rather than understanding. So this panel
 * lets someone pick a round, change the price to whatever they want, and watch the deployed
 * contract refuse it.
 *
 * Nothing here is a simulation. `Ladder.provenClose` is the same call `Market.settle` makes before
 * it pays anybody out (src/Market.sol:204), it is a `view` so it costs nothing and needs no
 * wallet, and the Merkle root it checks against sits in the contract's storage where no argument
 * to the call can reach it. The visitor's only real option is the one the protocol anticipates:
 * post their own checkpoint and stake a bond against it.
 */
import { addresses, provenClose, type LeafClaim } from "./chain.js";
import {
  deriveEpoch,
  epochRange,
  leafHash,
  merkleProof,
  merkleRoot,
  type Leaf,
  type RoomSpec,
} from "./protocol.js";
import { EXPLORER } from "./deployments.js";
import { chip } from "./explain.js";

const hex = (b: Uint8Array) => "0x" + [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
const short = (s: string, n = 10) => `${s.slice(0, 2 + n)}…${s.slice(-6)}`;

/** The disproof that already happened on-chain, for the moment someone asks "so post your own". */
const REAL_DISPROOF = "0x35b60b28ae9480a74b364f57ae80b975911f99d7cc1731dd7410a21a8bd713cf";

export interface RigTarget {
  spec: RoomSpec;
  epoch: bigint;
  /** The root the contract holds. Read from chain, never from here. */
  committedRoot: string;
}

interface RigState {
  leaves: Leaf[];
  hashes: Uint8Array[];
  index: number;
  /** The visitor's price for the selected round, in WAD. */
  tampered: bigint;
}

let st: RigState | null = null;

function fmt(v: bigint, decimals = 4): string {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const whole = a / 10n ** 18n;
  const frac = (a % 10n ** 18n).toString().padStart(18, "0").slice(0, decimals);
  return `${neg ? "-" : ""}${whole.toLocaleString("en-US")}${decimals ? "." + frac : ""}`;
}

/** Parses a decimal the visitor typed into WAD, without ever touching a float. */
function parseWad(text: string): bigint | null {
  const t = text.trim().replace(/,/g, "");
  if (!/^-?\d*(\.\d*)?$/.test(t) || t === "" || t === "-" || t === ".") return null;
  const neg = t.startsWith("-");
  const [whole, frac = ""] = (neg ? t.slice(1) : t).split(".");
  const padded = (frac + "0".repeat(18)).slice(0, 18);
  const v = BigInt(whole || "0") * 10n ** 18n + BigInt(padded || "0");
  return neg ? -v : v;
}

/** The 20 committed closes, with the selected one shown as the visitor has left it. */
function bars(): string {
  if (!st) return "";
  const W = 1000;
  const H = 150;
  const n = st.leaves.length;

  const shown = st.leaves.map((l, i) => (i === st!.index ? st!.tampered : l.close));
  let lo = shown[0]!;
  let hi = shown[0]!;
  for (const v of shown) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  const span = hi - lo === 0n ? 1n : hi - lo;
  const y = (v: bigint) => 12 + (H - 36) * (1 - Number(((v - lo) * 10_000n) / span) / 10_000);
  const x = (i: number) => 8 + ((W - 56) * i) / Math.max(1, n - 1);

  const path = shown.map((v, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");
  const dots = shown
    .map((v, i) => {
      const on = i === st!.index;
      return `<circle cx="${x(i).toFixed(1)}" cy="${y(v).toFixed(1)}" r="${on ? 6 : 3}"
        fill="${on ? "var(--bad)" : "var(--dimmer)"}" stroke="${on ? "var(--bad)" : "none"}"
        style="cursor:pointer" data-i="${i}"><title>round ${st!.leaves[i]!.round}</title></circle>`;
    })
    .join("");

  return `<svg viewBox="0 0 ${W} ${H}" id="rig-chart" style="width:100%;height:auto;overflow:visible"
    role="img" aria-label="The committed epoch. Click a round to tamper with its price.">
    <path d="${path}" fill="none" stroke="var(--dim)" stroke-width="1.5"/>
    ${dots}
  </svg>`;
}

function controls(): string {
  if (!st) return "";
  const leaf = st.leaves[st.index]!;
  const honest = leaf.close;
  const changed = st.tampered !== honest;
  const delta = st.tampered - honest;

  return `
  <div class="controls" style="margin:16px 0 6px">
    <label class="label" style="margin:0">round ${leaf.round.toLocaleString("en-US")} close</label>
    <input id="rig-price" type="text" inputmode="decimal" value="${fmt(st.tampered, 6)}"
      style="width:190px" aria-label="Your price for this round" />
    <button id="rig-moon">Moon it</button>
    <button id="rig-crash">Crash it</button>
    <button id="rig-one">+1 unit</button>
    <button id="rig-reset">Honest value</button>
  </div>
  <div class="note" style="margin:0 0 16px">
    ${
      changed
        ? `You have moved it by <strong style="color:var(--bad)">${delta > 0n ? "+" : ""}${fmt(delta, 6)}</strong>.
           The smallest change this encoding can express is 10<sup>-18</sup> &mdash; and it is caught
           exactly as decisively as a large one, because the contract asks whether the value
           <em>equals</em> the committed one, not whether it is close.`
        : `This is the honest value, derived in this browser from the beacon. Change it and ask again.`
    }
  </div>
  <div class="controls" style="margin:0">
    <button id="rig-ask" class="primary">Ask Monad to accept this price</button>
    <span class="note" style="margin:0">
      A free <code>eth_call</code> to <code>Ladder.provenClose</code> &mdash; the same call that
      settles markets. No wallet, no gas, no signature.${chip("merkle")}
    </span>
  </div>
  <div id="rig-verdict" style="margin-top:18px"></div>`;
}

function render(host: HTMLElement, target: RigTarget): void {
  const [r0, r1] = epochRange(target.spec, target.epoch);
  host.innerHTML = `
    <div class="label">try to rig it${chip("rig")}</div>
    <p class="note" style="margin:0 0 4px">
      Epoch ${target.epoch} of this Room &mdash; rounds ${r0.toLocaleString("en-US")}&ndash;${r1.toLocaleString("en-US")}
      &mdash; is <strong>finalised</strong> on Monad. Click any round below, set its price to whatever
      suits you, and ask the contract that settles markets to accept it.
    </p>
    ${bars()}
    <div id="rig-controls">${controls()}</div>`;

  host.querySelectorAll<SVGCircleElement>("#rig-chart circle").forEach((c) =>
    c.addEventListener("click", () => {
      if (!st) return;
      st.index = Number(c.dataset.i);
      st.tampered = st.leaves[st.index]!.close;
      render(host, target);
    }),
  );

  const price = host.querySelector<HTMLInputElement>("#rig-price");
  const redraw = () => render(host, target);
  const set = (v: bigint) => {
    if (!st) return;
    st.tampered = v;
    redraw();
  };

  price?.addEventListener("change", () => {
    const v = parseWad(price.value);
    if (v !== null) set(v);
    else redraw();
  });

  host.querySelector("#rig-moon")?.addEventListener("click", () => set((st!.tampered * 150n) / 100n));
  host.querySelector("#rig-crash")?.addEventListener("click", () => set((st!.tampered * 50n) / 100n));
  host.querySelector("#rig-one")?.addEventListener("click", () => set(st!.tampered + 1n));
  host.querySelector("#rig-reset")?.addEventListener("click", () => set(st!.leaves[st!.index]!.close));
  host.querySelector("#rig-ask")?.addEventListener("click", () => void ask(host, target));
}

async function ask(host: HTMLElement, target: RigTarget): Promise<void> {
  if (!st) return;
  const out = host.querySelector<HTMLElement>("#rig-verdict");
  if (!out) return;
  out.innerHTML = `<p class="note">Asking the contract…</p>`;

  const leaf = st.leaves[st.index]!;
  const honest = st.tampered === leaf.close;

  // The siblings are the honest ones. A tampered leaf hashes differently, so the path no longer
  // reaches the committed root -- which is the whole mechanism, visible in one call.
  const claim: LeafClaim = {
    round: leaf.round,
    close: st.tampered,
    high: leaf.high,
    low: leaf.low,
    path: merkleProof(st.hashes, st.index).map((p) => hex(p) as `0x${string}`),
  };

  const res = await provenClose(target.spec, target.epoch, claim);

  // What the lie would need the tree to look like, for the "I would rebuild it" objection.
  const forged = hex(
    merkleRoot(
      st.leaves.map((l, i) => leafHash(i === st!.index ? { ...l, close: st!.tampered } : l)),
    ),
  );

  if (res.ok) {
    out.innerHTML = `
      <span class="badge good">accepted &mdash; ${fmt(res.close, 6)}</span>
      <p class="note" style="margin:12px 0 0">
        The contract acknowledged this price, because the leaf is in the Merkle tree it has in
        storage. This is the number <code>Market.settle</code> would pay out on. Now change it.
      </p>`;
    return;
  }

  out.innerHTML = `
    <span class="badge bad">refused &mdash; ${res.error}${res.detail ? `(${res.detail})` : ""}</span>
    <p class="note" style="margin:12px 0 10px">
      ${
        res.error === "LeafNotCommitted"
          ? `The contract will not acknowledge a price that is not in the tree it committed to.
             ${honest ? "" : "Your price is not in that tree, so there is nothing to settle against."}`
          : `The call did not get as far as your price.`
      }
    </p>
    <table>
      <tr><td>root held by the contract${chip("leafproof")}</td><td>${short(target.committedRoot, 14)}</td></tr>
      <tr><td>root your price needs</td><td style="color:var(--bad)">${short(forged, 14)}</td></tr>
    </table>
    <p class="note" style="margin:12px 0 0">
      You could of course rebuild the whole tree so your price fits &mdash; that second root is what
      it would be. But you do not get to hand the contract a root. It already has one, in storage,
      at <a href="${EXPLORER}/address/${addresses.ladder}" target="_blank" rel="noreferrer">this address</a>.
      The only way in is to post your own checkpoint and put up a bond, and then anyone who
      re-derives the beacon can take it. <a href="${EXPLORER}/tx/${REAL_DISPROOF}" target="_blank" rel="noreferrer">Somebody already tried.</a>
    </p>`;
}

/** Derives the finalised epoch locally, then hands over the attacker's seat. */
export async function mountRig(
  host: HTMLElement,
  target: RigTarget,
  drand: Parameters<typeof deriveEpoch>[2],
): Promise<void> {
  host.innerHTML = `<div class="label">try to rig it</div>
    <p class="note">Re-deriving the finalised epoch from the beacon…</p>`;

  const { path } = await deriveEpoch(target.spec, target.epoch, drand);
  const local = hex(path.merkleRoot);
  if (local.toLowerCase() !== target.committedRoot.toLowerCase()) {
    // Refusing to continue is the honest move: the panel's whole claim is that the tree below is
    // the one the contract holds, and here it demonstrably is not.
    host.innerHTML = `<div class="label">try to rig it</div>
      <span class="badge bad">cannot set this up</span>
      <p class="note" style="margin-top:12px">
        The epoch this browser derives does not match the root on Monad, so there is no honest
        baseline to tamper with. That disagreement is itself the interesting thing, and the panel
        above reports it.
      </p>`;
    return;
  }

  const mid = Math.floor(path.leaves.length / 2);
  st = {
    leaves: path.leaves,
    hashes: path.leafHashes,
    index: mid,
    tampered: path.leaves[mid]!.close,
  };
  render(host, target);
}
