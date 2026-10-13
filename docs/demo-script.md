# Technical demo — 2:35, against a 3:00 cap

Two beats are the submission: a lie caught, and a bettor paid. Everything else exists to make those
two mean something.

The lie is shown twice on purpose, and the order matters. First in the browser, where it takes five
seconds and the viewer could do it themselves; then in the terminal, where a bond actually moves.
The first beat makes the second legible — without it, the terminal is a person typing while prices
scroll past.

Written to 2:35 so a slow take still lands under the cap. Say these lines in your own words; they
are timed to be spoken at a normal pace, not read.

## Before recording

```bash
make web && cd web && python3 -m http.server 8173
```

Check the frame for keystore prompts and funded balances before publishing — the recording is a
screen, and a leaked key is expensive on a deadline.

Open the app once and **let it settle before recording**: the chart derives 240 rounds, the rig
panel re-derives the finalised epoch, and the guided tour opens itself on a first visit. Dismiss
the tour, then reload — it only auto-opens once per browser, which is the behaviour a judge gets
and not the one you want mid-take. To get the first-visit behaviour back for a take that shows it:

```bash
# in the browser console
localStorage.removeItem("croom.tour.seen")
```

For the two-account fraud proof, have a second keystore ready and funded:

```bash
cast wallet import croom-challenger --interactive
make fund-challenger TO=<challenger address>      # 0.2 MON, gas only: the challenger posts no bond
```

## 0:00 — the claim (15s)

Open on the app. Drand head and proven floor side by side.

> "This is a price chart, but there's no asset behind it. It's generated from a public randomness
> beacon that signs a value every three seconds. Nobody can predict it, nobody can move it, and
> anyone can recompute it."

## 0:15 — computed here, not fetched (25s)

Click **Derive chart**.

> "The page is fetching beacon signatures, verifying each one, and deriving every price right here.
> Watch the counter."

Land on **zero RPC calls**.

> "Two hundred and forty rounds, derived in this browser. Not one request to the blockchain. If
> Monad were unreachable right now, this chart would still be correct."

## 0:40 — try to rig it (40s)

Scroll to **try to rig it**. Free `eth_call`, no wallet — it cannot fail on camera for any reason a
reload won't fix.

Ask with the honest value first.

> "This price is from an epoch finalised on Monad. I'm asking the contract to confirm it — the same
> call the market makes before it pays anyone out. Accepted."

Click **+1 unit**, ask again. Let the refusal sit.

> "I've moved it by ten to the minus eighteen. The smallest lie this encoding can express.
> Refused — not because it's implausible, but because it isn't in the batch the contract committed
> to."

Point at the two roots.

> "And you can't rebuild the batch to fit. You don't get to hand the contract a root. It already
> has one."

Click **Crash it**, ask once more.

> "A blatant lie, refused exactly as firmly. It asks whether the value *equals* what the beacon
> produced, never whether it's close."

## 1:20 — the same lie, with money on it (45s)

Terminal, two accounts visible.

```bash
make demo-post-lie LADDER=0x1bE27643FF478ef280a903831F0927ef68f4374c ACCOUNT=croom-liar FROM=<liar>
```

> "A checkpoint for twenty rounds. Nineteen honest, one wrong by a single unit — and a bond that
> says it's correct."

```bash
make demo-disprove LADDER=0x1bE27643FF478ef280a903831F0927ef68f4374c ACCOUNT=croom-challenger FROM=<challenger>
```

> "Different account. Nothing passed between them. It re-derives the same rounds from the public
> beacon, finds the one that doesn't follow, and proves it in a single transaction — with no bond
> of its own."

Explorer: **Rejected**, bond moved.

> "Same refusal you just watched in the browser, except this time somebody had money on it."

## 2:05 — and a bettor gets paid (20s)

Already on-chain, so show transactions rather than perform it live.

> "Two accounts, opposite sides of a window. Settlement doesn't ask an oracle what the price was —
> it's *shown* the open and the close, each with a Merkle path into an epoch the ladder already
> finalised."

Settle transaction, then the claim.

> "Twenty staked, forty-nine and a half back. One percent rake, published up front."

## 2:25 — close (10s)

> "Four contracts on Monad. The maths is bit-exact against a Rust implementation written before
> this one, across twenty thousand rounds. There's a transaction hash for the lie that got caught,
> and another where somebody got paid from a price nobody could have moved."
>
> "Try to rig it yourself. No wallet, nothing to install."

Land on the app with the interactive panels in frame.

## What not to claim

- Not that Monad is the only chain this runs on. The reference runs on Solana. The *cadence* is what Monad unlocks.
- Not that the protocol was designed this fortnight. It was not, and the README says so.
- Not that the floor-freshness issue is solved. It is reported, demonstrated by a test, and open.
- Not that the market has depth or a history. **One** market has been opened and settled, by two
  accounts, for five cents in total. The mechanism is proven; the volume is nothing and saying
  otherwise invites exactly the question you cannot answer.
- Not that anything runs unattended. Every post, floor advance and settlement so far was a command
  somebody typed.
- Not that the rig panel is a simulation or a mock. It is worth saying out loud that it calls the
  deployed contract, because it looks like a toy and the instinct will be to assume it is one.
