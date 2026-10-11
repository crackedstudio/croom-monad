# Demo video — three and a half minutes, or three without **0:50**

Two beats are the submission: a lie caught, and a bettor paid. Everything else exists to make those
two mean something.

The lie is now shown twice on purpose, and the order matters. First in the browser, where it takes
five seconds and the viewer could do it themselves; then in the terminal, where a bond actually
moves. The first beat makes the second one legible — without it, the terminal is a person typing
while prices scroll past. If a hard three-minute cap forces a cut, drop **0:50**.

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

## 0:00 — the claim (20s)

A judge arriving cold gets the guided tour automatically, so it is worth knowing it exists before
you decide whether to show it. It is not part of this script's timing — mention it at the close
rather than walking it, because narrating a tour of your own tour is how two minutes disappear.

> "This is a price chart. It isn't a real asset — it's generated from a public randomness beacon
> that publishes a signed value every three seconds. Nobody can predict it, nobody can influence
> it, and anyone can recompute it."

Show the page. Point at the drand head and the proven floor side by side.

## 0:20 — it is computed here, not fetched (30s)

Click **Derive chart**. While it runs:

> "The page is fetching beacon signatures, verifying each one in the browser, and deriving every
> price itself. Watch the RPC counter."

Land on **zero RPC calls** and the room id **matches**.

> "Two hundred and forty rounds, derived in this browser. Not one request to the blockchain. If
> Monad were unreachable right now, this chart would still be right."

## 0:50 — the chain agrees, or it doesn't (25s)

Scroll to **verify against chain**.

> "Now we ask Monad. It holds a thirty-two byte commitment for this epoch — and the root computed
> here does not match it."

Point at the two roots, then at **rejected**.

> "Somebody posted a false commitment. They've already lost their bond."

## 1:15 — try to rig it yourself (35s)

Scroll to **try to rig it**. This is the beat that makes the idea land, and nothing in it needs a
wallet — it is a free `eth_call` against the deployed contract, so it cannot fail on camera for any
reason a reload will not fix.

Click **Ask Monad to accept this price** with the honest value first.

> "This is a price from an epoch that's finalised on Monad. I'm asking the contract to confirm it —
> and this is the same call the market makes before it pays anybody out. It accepts it."

Now click **+1 unit**, then ask again.

> "I've changed it by one unit. Ten to the minus eighteen — the smallest lie this encoding can
> express. Same question."

Let the refusal sit on screen for a moment.

> "Refused. Not because the number is implausible, but because it isn't in the batch the contract
> committed to. And the obvious objection — rebuild the whole batch so my price fits — is answered
> right here: that's the root it would need. But you don't get to hand the contract a root. It
> already has one."

Then try **Crash it** and ask once more.

> "A blatant lie is refused exactly as firmly as a one-unit one. The contract asks whether the value
> *equals* what the beacon produces, never whether it's close."

## 1:50 — the liar, live, with real money (50s)

Now the same lie where a bond is actually at stake. Terminal, two accounts visible:

```bash
make demo-post-lie LADDER=0x1bE27643FF478ef280a903831F0927ef68f4374c ACCOUNT=croom-liar FROM=<liar>
```

> "I'm posting a checkpoint for twenty rounds. Nineteen are honest. One price is wrong — by one
> unit. Ten to the minus eighteen. The smallest lie this encoding can express. And I'm putting up a
> bond that says it's correct."

```bash
make demo-disprove LADDER=0x1bE27643FF478ef280a903831F0927ef68f4374c ACCOUNT=croom-challenger FROM=<challenger>
```

> "Different account. Nothing passed between them. This one re-derives the same twenty rounds from
> the public beacon, finds the leaf that doesn't follow, and proves it on chain — in one
> transaction, with no bond of its own."

Show the explorer: **status Rejected**, bond moved.

> "That's the same refusal you just watched in the browser, except this time somebody had money on
> it. One unit at the eighteenth decimal place, and the bond is gone."

## 2:40 — and a bettor gets paid (30s)

This is the part that makes it a market rather than a demo. It is already on-chain, so it can be
shown as transactions rather than performed live.

```bash
make print-market-values        # free; shows state, winner, rake owed, who can claim
```

> "A price nobody controls is only useful if you can trade on it. So: two accounts, opposite
> sides, three cents between them."

Point at the two stake transactions, from two unrelated addresses.

> "Settlement doesn't ask an oracle what the price was. It's *shown* the price — the open and the
> close of the window — each with a Merkle path proving that value is in an epoch the ladder has
> already finalised. A checkpoint still inside its challenge window is refused, so a payout can
> never rest on a number the fraud proof might overturn."

Show the settle transaction, then the claim.

> "Twenty staked, forty-nine and a half returned. One percent rake, published up front, credited to
> the room's creator — credited, not sent, because a creator whose address reverts shouldn't be able
> to freeze everybody else's money."

The contract's remaining balance is exactly the unwithdrawn rake. Nothing else is held.

## 3:10 — close (20s)

> "Four contracts on Monad. Fifty rooms anyone can open and nobody can change. The maths is
> bit-exact against a Rust implementation written before this one existed, across twenty thousand
> rounds."
>
> "Verifying one beacon round costs six hundred and fifty thousand gas here — ninety-seven percent
> of it a single pairing. Verifying every round would cost sixteen hundred MON a day, which is why
> the chain commits instead of verifies, and why the fraud proof has to work."
>
> "It does. There's a transaction hash for it — and another one where somebody got paid from a
> price that no one, including us, could have moved."

Land on the app with the interactive panels in frame.

> "And none of this is a video you have to take my word for. Open the page, press 'show me around',
> and every part of it explains itself — then try to rig it yourself. No wallet, nothing to install,
> nothing it can cost you."

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
