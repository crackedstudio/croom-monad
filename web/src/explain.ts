/**
 * Explainers: a modal per idea, and a guided tour that strings them together.
 *
 * The page is dense with things that are obvious only once somebody tells you — a proven floor, a
 * checkpoint, a bond, a parimutuel pool. A visitor who does not already know what those are will
 * read the panels as decoration, which wastes the only few minutes they will ever spend here.
 *
 * So every term that carries weight gets a marker next to it, and every marker opens a short piece
 * of plain language that says what the thing is and, more importantly, why it exists. The tour
 * walks the same content in the order the argument is built, for someone who would rather be led.
 *
 * Content lives here rather than in the panels because the same idea surfaces in several places —
 * "epoch" appears in the spec table, the verification panel and the rig panel — and three
 * explanations that drift apart are worse than none.
 */

export interface Explainer {
  title: string;
  /** Plain language first. HTML, because some of these need a table or an emphasis. */
  body: string;
}

const E: Record<string, Explainer> = {
  // ── the beacon and the chain's view of it ──────────────────────────────────────────────────
  beacon: {
    title: "The drand beacon",
    body: `
      <p>A group of independent organisations — the League of Entropy — jointly produce one random
      number every three seconds. No single member can choose it, skip it, or work out the next one
      early, because producing it requires enough of them to co-operate and the result is a
      signature nobody can forge.</p>
      <p>Every value is public and permanent. Anyone can fetch round 21,408,246 forever, check the
      signature, and get the same answer. <strong>That is the raw material every price on this page
      is made from.</strong></p>
      <p class="note">The scheme is <code>bls-bn254-unchained-on-g1</code>. "Unchained" means each
      round stands alone and does not depend on the previous one, which is what lets anybody verify
      a single round without replaying history.</p>`,
  },
  floor: {
    title: "The proven floor",
    body: `
      <p>The chain cannot see the beacon by itself. Someone has to bring it a signed round and the
      contract checks the signature. The <strong>proven floor</strong> is the highest round anyone
      has proved to it so far — the chain's honest answer to "what time is it?"</p>
      <p>It only ever goes up, and it is never guessed from a block timestamp. A timestamp is set
      by whoever produced the block, so a rule written against it is a rule the block producer can
      bend. A rule written against the floor can only be satisfied by showing a real signature.</p>
      <p class="note">Checking one round costs about 657,000 gas, almost all of it a single pairing
      operation. That price is exactly why the chain commits to batches and lets anyone challenge
      them, rather than verifying every round itself.</p>`,
  },
  staleness: {
    title: "Why a stale floor matters",
    body: `
      <p>Nothing on this project runs unattended, so the floor is only as fresh as the last time
      somebody advanced it by hand. The gap you see is how far behind the chain's clock is.</p>
      <p>The interesting part is the direction of the damage. Two fairness rules compare against the
      floor: a new Room must start above it, and a market can only be entered while its first round
      is still above it. <strong>A floor that lags makes both rules weaker, not stronger</strong> —
      it admits rounds that are already public and could in principle have been looked at.</p>
      <p class="note">The protocol specification states this the other way round. We report it as a
      finding rather than quietly implementing the version that suits us; there is a test that
      demonstrates it and a write-up in the repository.</p>`,
  },

  // ── what a Room is ─────────────────────────────────────────────────────────────────────────
  room: {
    title: "A Room",
    body: `
      <p>A Room is a complete recipe for turning beacon randomness into a price series: which
      family of motion, how volatile, what it opens at, how many steps per round, where it starts.</p>
      <p>Hand that recipe and the public beacon to any two people and they will produce byte-identical
      prices, forever, without talking to each other. There is no server, no feed and no publisher.
      <strong>The price is not reported. It is derived.</strong></p>`,
  },
  roomid: {
    title: "The room id",
    body: `
      <p>The id is the hash of the recipe itself. Change the volatility by one part in a billion and
      you get a different id.</p>
      <p>So there is no such thing as editing a Room — only a different Room that nobody has opened.
      <strong>Whoever created a Room has no more power over it than you do</strong>, which is the
      property that makes the rest of the system worth building.</p>
      <p class="note">Try it: move a slider in "Open your own Room" and watch the id change under
      your hand.</p>`,
  },
  family: {
    title: "Families",
    body: `
      <p>How the price moves between rounds.</p>
      <p><strong>Drift</strong> is geometric Brownian motion — the familiar shape, with a volatility
      figure quoted per year. <strong>Step</strong> is a coin flip each sub-tick that adds or
      subtracts a fixed amount, floored so the price can never reach zero.</p>
      <p class="note">The deployed contract compiles these two and reverts on anything else. The
      specification describes six more; implementing them on-chain without the vectors to prove
      them bit-exact would be a claim rather than a feature.</p>`,
  },
  subticks: {
    title: "Sub-ticks",
    body: `
      <p>How many times the price moves inside a single three-second round. More sub-ticks means a
      busier path between the open and the close.</p>
      <p>They matter because the high and the low of a round are recorded, not just the close. A
      payoff that asks "did it ever touch this level?" needs to know what happened <em>during</em>
      the round, not only where it ended.</p>`,
  },
  volatility: {
    title: "Volatility",
    body: `
      <p>How violently the price moves, quoted the way finance quotes it: annualised. 75% a year is
      an energetic stock. The numbers reachable here go far beyond anything real, because a Room is
      not pretending to be an asset.</p>
      <p class="note">Internally this is scaled to a three-second step and corrected by minus one
      half sigma squared, so that the average price neither drifts up nor down over time. Without
      that correction a high-volatility Room would silently trend upward and the market built on it
      would be biased from the first round.</p>`,
  },
  epoch: {
    title: "Epochs",
    body: `
      <p>A fixed-length run of rounds — twenty, for these Rooms — treated as one unit for
      bookkeeping.</p>
      <p>Nobody commits to prices one at a time; that would cost far too much. An epoch is
      summarised into a single hash and that hash is what goes on-chain.</p>`,
  },

  // ── the chain's commitment and how it is policed ───────────────────────────────────────────
  merkle: {
    title: "The Merkle root",
    body: `
      <p>A way to compress many values into one hash, such that you can later prove any single value
      was among them without revealing or re-sending the rest.</p>
      <p>Twenty prices go in; thirty-two bytes come out. To prove round 21,193,065 closed at a
      particular price you supply that price plus a short list of sibling hashes, and the contract
      recomputes its way to the root it already holds. If it arrives at the same root, the price was
      in the batch. <strong>If it arrives anywhere else, the price is refused.</strong></p>
      <p class="note">You cannot hand the contract a root. It has one, in its own storage. That is
      the whole reason the rig panel below cannot be beaten by supplying better arguments.</p>`,
  },
  checkpoint: {
    title: "Checkpoints and the challenge window",
    body: `
      <p>A <strong>checkpoint</strong> is somebody's claim that an epoch's prices hash to a
      particular root. Posting one requires a bond.</p>
      <p>It is not checked when it arrives — checking would mean verifying twenty beacon rounds,
      which is ruinous. Instead it sits <strong>pending</strong> for a challenge window. Anyone who
      re-derives the epoch from the public beacon and finds it wrong can prove that in one
      transaction and take the bond. If nobody does, it becomes <strong>final</strong>.</p>
      <table>
        <tr><td>pending</td><td>posted, still challengeable, not yet usable for settlement</td></tr>
        <tr><td>final</td><td>the window passed unchallenged; markets may settle against it</td></tr>
        <tr><td>rejected</td><td>proved wrong; the bond went to whoever proved it</td></tr>
      </table>`,
  },
  bond: {
    title: "The bond",
    body: `
      <p>Money the poster puts at risk to make the claim. It is returned when the checkpoint
      finalises and forfeited to the challenger when it does not.</p>
      <p>The asymmetry is deliberate: <strong>challenging costs nothing but gas.</strong> A
      challenger puts up no stake of their own, so the cheapest way to make money from a liar is to
      catch them, and the cheapest way to avoid losing money is to be honest.</p>`,
  },
  disproof: {
    title: "How a lie is caught",
    body: `
      <p>A challenger names two neighbouring rounds in the batch and says: the second does not
      follow from the first. They supply the beacon signature for that round.</p>
      <p>The contract verifies the signature, re-executes that single step of the price rule, and
      compares. One step, one transaction, no back-and-forth game. If the committed value differs by
      even 10<sup>-18</sup>, the checkpoint is rejected and the bond moves.</p>
      <p class="note">This has happened on this chain, with a one-unit lie, between two addresses
      that passed nothing to each other. The transaction is linked from the landing page.</p>`,
  },
  rpc: {
    title: "Why the call counter is here",
    body: `
      <p>"Computed in your browser, not fetched from a server" is easy to say and easy to get
      quietly wrong, so this page counts its own network traffic to the blockchain while it draws
      the chart.</p>
      <p>It should read <strong>zero</strong>. The chain is consulted afterwards, to compare notes —
      and if it were unreachable entirely, every price above would still be correct.</p>`,
  },

  // ── contracts ──────────────────────────────────────────────────────────────────────────────
  contracts: {
    title: "The four contracts",
    body: `
      <table>
        <tr><td>Entropy</td><td>verifies beacon signatures and keeps the proven floor</td></tr>
        <tr><td>Registry</td><td>opens Rooms; a Room is its specification, stored by its hash</td></tr>
        <tr><td>Ladder</td><td>holds checkpoints, bonds, the challenge window and the disproof</td></tr>
        <tr><td>Market</td><td>parimutuel pools that settle against finalised prices only</td></tr>
      </table>
      <p class="note">Each address links to the explorer. Everything on this page can be checked
      against them without asking us for anything.</p>`,
  },
  market: {
    title: "How the betting works",
    body: `
      <p><strong>Parimutuel</strong>, like a racecourse tote. Everyone backing "up" shares one pool,
      everyone backing "down" shares the other, and the winning side splits the lot in proportion to
      what they put in. There is no counterparty and no house taking the other side of your
      position, so the protocol itself can never be on the hook.</p>
      <p>A published 1% rake goes to the Room's creator. It is <em>credited</em> rather than sent,
      because a creator whose address rejects payments must not be able to freeze everybody else's
      settlement.</p>
      <p>Settlement takes two prices — the window's open and close — each proved to belong to a
      <strong>finalised</strong> epoch. A pending checkpoint is refused outright: paying out on a
      number the fraud proof might still overturn would make the fraud proof pointless.</p>`,
  },

  // ── the interactive panels ─────────────────────────────────────────────────────────────────
  compose: {
    title: "Open your own Room",
    body: `
      <p>Set the parameters and watch the <strong>room id change as you move things</strong>. That is
      the point of the panel: the id is the hash of the recipe, so a different parameter is a
      different Room rather than an edited one.</p>
      <p>The preview is drawn from past beacon rounds so that you can see immediately what the
      settings do. A Room you actually registered could not start in the past — the Registry
      requires its first round to sit above the proven floor, which is what stops anyone choosing a
      Room whose outcome they have already seen.</p>`,
  },
  predict: {
    title: "Call the next tick",
    body: `
      <p>The chart is advancing in real time, one price every three seconds as the beacon signs.</p>
      <p>Say which way the next one goes. <strong>The round you are guessing on has not been
      published yet</strong> — the panel checks, and if this tab has fallen behind it catches up to
      the live beacon first rather than letting you guess on a round that already exists.</p>
      <p>Play twenty and watch your hit rate settle on 50%. No reading of the chart moves it,
      because the next value is a signature nobody has produced yet. That is the entire claim,
      and it is more convincing to lose to it than to read it.</p>`,
  },
  rig: {
    title: "Try to rig it",
    body: `
      <p>This epoch is finalised on Monad. Pick any round, set the price to whatever suits you, and
      ask the contract to accept it.</p>
      <p>The call is <code>Ladder.provenClose</code> — <strong>the same call the market makes before
      it pays anybody out.</strong> It is a read-only call, so it costs nothing, needs no wallet and
      cannot be a trick: the Merkle root it checks against lives in the contract's storage, where no
      argument you supply can reach it.</p>
      <p>Try the honest value first and watch it be accepted. Then move it by a single unit — one
      part in 10<sup>18</sup> — and watch it be refused exactly as firmly as if you had doubled it.
      The contract asks whether the value <em>equals</em> what was committed, never whether it is
      close.</p>`,
  },
  leafproof: {
    title: "The two roots",
    body: `
      <p>When your price is refused, the panel shows you the root the contract holds and the root
      your price would need.</p>
      <p>The obvious objection is: why not rebuild the whole batch so my price fits? You can — that
      second root is what you would get. But <strong>you do not get to hand the contract a
      root.</strong> It already has one. Your only route is to post your own checkpoint, put up a
      bond, and survive the challenge window while anyone in the world can re-derive the beacon and
      take that bond off you.</p>`,
  },
};

// ── modal ────────────────────────────────────────────────────────────────────────────────────

let dialog: HTMLDialogElement | null = null;

function ensureDialog(): HTMLDialogElement {
  if (dialog) return dialog;
  dialog = document.createElement("dialog");
  dialog.className = "explain";
  dialog.innerHTML = `
    <div class="explain-head">
      <h3 id="explain-title"></h3>
      <button class="explain-close" aria-label="Close">✕</button>
    </div>
    <div class="explain-body" id="explain-body"></div>
    <div class="explain-foot">
      <span class="note" style="margin:0">Esc closes this.</span>
      <button class="explain-next" id="explain-next" hidden></button>
    </div>`;
  document.body.appendChild(dialog);
  dialog.querySelector(".explain-close")!.addEventListener("click", () => close());
  // Clicking the backdrop: a click whose target is the dialog itself landed outside the content.
  dialog.addEventListener("click", (e) => {
    if (e.target === dialog) close();
  });
  // Only a real dismissal clears the spotlight. Switching a step between modal and non-modal has
  // to close the dialog first, and that close would otherwise wipe the highlight just set up.
  //
  // The check is on the resulting state rather than on a flag set around the close: the `close`
  // event arrives asynchronously, by which time any synchronous "I am only switching" marker has
  // already been unset. Asking a tick later whether the dialog ended up open answers the question
  // the flag was trying to answer, and does so however the event is scheduled.
  dialog.addEventListener("close", () => {
    setTimeout(() => {
      if (!dialog?.open) clearSpotlight();
    }, 0);
  });
  return dialog;
}

function close(): void {
  dialog?.close();
  clearSpotlight();
}

/**
 * Shows the dialog modally, or not.
 *
 * `showModal()` makes the rest of the document inert, which also blocks it from scrolling — so a
 * tour step could spotlight a panel far down the page and then be unable to bring it into view.
 * Steps that point at something therefore open *non*-modally and let the spotlight's own shadow do
 * the dimming; the page stays scrollable, and a visitor can even poke at the panel being described.
 * Switching between the two needs a close first, because a dialog cannot change mode while open.
 */
function present(d: HTMLDialogElement, modal: boolean): void {
  if (d.open && d.dataset.modal === String(modal)) return;
  if (d.open) d.close();
  d.dataset.modal = String(modal);
  if (modal) d.showModal();
  else d.show();
}

export function openExplainer(key: string): void {
  const item = E[key];
  if (!item) return;
  const d = ensureDialog();
  (d.querySelector("#explain-title") as HTMLElement).textContent = item.title;
  (d.querySelector("#explain-body") as HTMLElement).innerHTML = item.body;
  (d.querySelector("#explain-next") as HTMLElement).hidden = true;
  clearSpotlight();
  present(d, true);
}

/** The marker that sits next to a term. */
export function chip(key: string): string {
  const item = E[key];
  if (!item) return "";
  return `<button class="qmark" data-explain="${key}" aria-label="What is ${item.title}?" title="${item.title}">?</button>`;
}

// ── tour ─────────────────────────────────────────────────────────────────────────────────────

interface Step {
  /** Element to spotlight. Missing elements are skipped rather than breaking the tour. */
  target?: string;
  key?: string;
  title?: string;
  body?: string;
}

const TOUR: Step[] = [
  {
    title: "What this page is",
    body: `
      <p>Every price here is produced from a public randomness beacon by a rule anyone can run.
      Nobody publishes it, nobody can move it, and the blockchain is used to <em>police</em> it
      rather than to supply it.</p>
      <p>This tour takes about a minute. At the end there are three things you can try yourself,
      including putting a price you invented in front of the contract that pays people out.</p>
      <p class="note">Every "?" on the page opens an explanation like this one. Nothing here needs a
      wallet and nothing can cost you anything.</p>`,
  },
  { target: "#panel-head", key: "beacon" },
  { target: "#panel-floor", key: "floor" },
  { target: "#panel-stale", key: "staleness" },
  { target: "#panel-chart", key: "rpc" },
  { target: "#panel-spec", key: "roomid" },
  { target: "#panels", key: "checkpoint" },
  { target: "#compose", key: "compose" },
  { target: "#predict", key: "predict" },
  { target: "#rig", key: "rig" },
  {
    title: "That is the whole idea",
    body: `
      <p>A price nobody decides, a cheap way for a chain to commit to it, and a one-shot proof that
      takes money off anyone who lies about it. The market on top is almost an afterthought — it
      only works because the three things underneath do.</p>
      <p class="note">The writing section goes through all of it in plain language, and again in
      detail for people who want the mathematics.</p>`,
  },
];

let spotlit: HTMLElement | null = null;
let stepIndex = 0;

/** Clears the sticky navigation bar, so a spotlit panel is not tucked under it. */
const SCROLL_OFFSET = 86;

let scrolling = 0;

/**
 * Brings a panel into view, animating it by hand.
 *
 * `scrollIntoView` is not used because it does nothing at all while a dialog is open: it is called,
 * it returns, and the page stays where it was. An explicit tween has no such ambiguity.
 *
 * The tween is driven by animation frames, which a hidden tab does not get — so a page that is not
 * actually on screen scrolls instantly rather than stalling half way and looking broken when the
 * visitor comes back to it.
 */
function bringIntoView(node: HTMLElement): void {
  const to = Math.max(0, node.getBoundingClientRect().top + window.scrollY - SCROLL_OFFSET);
  const from = window.scrollY;
  const distance = to - from;
  if (Math.abs(distance) < 2) return;

  cancelAnimationFrame(scrolling);
  const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  if (reduced || document.hidden) {
    window.scrollTo(0, to);
    return;
  }

  const ms = Math.min(620, 220 + Math.abs(distance) * 0.18);
  const start = performance.now();
  const step = (now: number) => {
    const t = Math.min(1, (now - start) / ms);
    // Cubic ease-out: quick to commit, gentle to land.
    window.scrollTo(0, from + distance * (1 - Math.pow(1 - t, 3)));
    if (t < 1) scrolling = requestAnimationFrame(step);
  };
  scrolling = requestAnimationFrame(step);
}

function clearSpotlight(): void {
  spotlit?.classList.remove("spotlight");
  spotlit = null;
  dialog?.classList.remove("docked");
}

function showStep(i: number): void {
  stepIndex = i;
  const step = TOUR[i];
  if (!step) {
    close();
    return;
  }

  const content = step.key ? E[step.key] : undefined;
  const title = step.title ?? content?.title ?? "";
  const body = step.body ?? content?.body ?? "";

  const d = ensureDialog();
  (d.querySelector("#explain-title") as HTMLElement).textContent = title;
  (d.querySelector("#explain-body") as HTMLElement).innerHTML = body;

  const next = d.querySelector("#explain-next") as HTMLButtonElement;
  next.hidden = false;
  next.textContent = i === TOUR.length - 1 ? "Done" : `Next · ${i + 1} of ${TOUR.length}`;
  next.onclick = () => (i === TOUR.length - 1 ? close() : showStep(i + 1));

  clearSpotlight();
  // A centred dialog sits exactly where a centred scroll target lands, so a step would cover the
  // panel it is describing. With a target, the panel goes to the top and the dialog to the bottom.
  d.classList.toggle("docked", Boolean(step.target));
  present(d, !step.target);

  // After `present`, never before: scrolling the page requires the dialog to be non-modal already.
  if (step.target) {
    const node = document.querySelector<HTMLElement>(step.target);
    if (node) {
      node.classList.add("spotlight");
      spotlit = node;
      bringIntoView(node);
    }
  }
}

const SEEN = "croom.tour.seen";

export function startTour(): void {
  showStep(0);
  try {
    localStorage.setItem(SEEN, "1");
  } catch {
    // Private windows and blocked site data both throw here. Forgetting that the tour was seen is
    // a smaller problem than the page failing to open, so this is deliberately swallowed.
  }
}

function seen(): boolean {
  try {
    return localStorage.getItem(SEEN) === "1";
  } catch {
    return false;
  }
}

/**
 * Wires every marker on the page, and offers the tour to a first-time visitor.
 *
 * Delegated from the document so that panels which re-render — and most of them do, on every
 * slider move — do not need to re-attach anything.
 */
export function mountExplainers(): void {
  document.addEventListener("click", (e) => {
    const target = (e.target as HTMLElement | null)?.closest<HTMLElement>("[data-explain]");
    if (!target) return;
    e.preventDefault();
    const key = target.dataset.explain!;
    if (key === "__tour__") startTour();
    else openExplainer(key);
  });

  document.addEventListener("keydown", (e) => {
    if (!dialog?.open) return;
    // A non-modal dialog gets no Esc handling from the browser.
    if (e.key === "Escape") {
      e.preventDefault();
      close();
      return;
    }
    const next = dialog.querySelector("#explain-next") as HTMLButtonElement;
    if (e.key === "ArrowRight" && !next.hidden) showStep(stepIndex + 1);
    if (e.key === "ArrowLeft" && !next.hidden && stepIndex > 0) showStep(stepIndex - 1);
  });

  if (!seen()) {
    // Late enough that the first panels have rendered and the spotlight has something to land on.
    window.setTimeout(() => {
      if (!dialog?.open) startTour();
    }, 1200);
  }
}
