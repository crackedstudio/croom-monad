# Demo video — about 3 minutes

Two beats are the submission: a lie caught, and a bettor paid. Everything else exists to make those
two mean something. If a hard three-minute cap forces a cut, drop **0:50** — the fraud proof
re-establishes the same point more forcefully.

## Before recording

```bash
make web && cd web && python3 -m http.server 8173
```

Check the frame for keystore prompts and funded balances before publishing — the recording is a
screen, and a leaked key is expensive on a deadline.

For the two-account fraud proof, have a second keystore ready and funded:

```bash
cast wallet import croom-challenger --interactive
make fund-challenger TO=<challenger address>      # 0.2 MON, gas only: the challenger posts no bond
```

## 0:00 — the claim (20s)

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

## 0:50 — the chain agrees, or it doesn't (35s)

Scroll to **verify against chain**.

> "Now we ask Monad. It holds a thirty-two byte commitment for this epoch — and the root computed
> here does not match it."

Point at the two roots, then at **rejected**.

> "Somebody posted a false commitment. They've already lost their bond."

## 1:25 — the liar, live (60s)

Terminal, two accounts visible:

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

> "The bond is gone. A lie of one unit at the eighteenth decimal place, caught as decisively as a
> large one — because the contract asks whether the value *equals* what the beacon produces, not
> whether it's close."

## 2:25 — and a bettor gets paid (30s)

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

## 2:55 — close (25s)

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

## What not to claim

- Not that Monad is the only chain this runs on. The reference runs on Solana. The *cadence* is what Monad unlocks.
- Not that the protocol was designed this fortnight. It was not, and the README says so.
- Not that the floor-freshness issue is solved. It is reported, demonstrated by a test, and open.
- Not that the market has depth or a history. **One** market has been opened and settled, by two
  accounts, for five cents in total. The mechanism is proven; the volume is nothing and saying
  otherwise invites exactly the question you cannot answer.
- Not that anything runs unattended. Every post, floor advance and settlement so far was a command
  somebody typed.
