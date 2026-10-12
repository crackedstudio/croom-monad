# Submission form — copy/paste

Field-by-field. Character counts are measured, not estimated.

---

## Project name

```
Croom
```

---

## Short description (200 max)

The current draft stops at a comma. Completed:

```
A permissionless protocol for markets whose price series is generated from public randomness, so nobody — not the creator, not us, not a validator — can rig a price, predict it, or see it early.
```

---

## Describe what your project does and how it works (8,000 max)

```
WHAT IT IS

Croom turns a public randomness beacon into tradeable price series that nobody can rig — including the people who built it.

A "Room" is a specification: a family of motion, a volatility, an opening price, a first round. Hand that spec and the public drand beacon to any two people and they produce byte-identical prices, forever, without talking to each other. There is no price feed, no oracle, no publisher and no server. The price is not reported. It is derived.

THE PROBLEM

Every derivative and prediction market needs a price, and today that price comes from someone you trust: an oracle you trust not to lie, not to be bribed and not to go offline. Synthetic markets have it worse — the house generates the numbers, and "provably fair" usually means "trust our seed commitment."

Croom removes the trusted party rather than auditing it. The input is public, the rule is public, and the chain's only job is to catch anyone who lies about the output.

HOW IT WORKS

1. The beacon. drand evmnet — run by the League of Entropy — publishes a BLS signature every 3 seconds. No single member can choose it, skip it or compute it early. Each round's randomness is SHA-256 of that signature. Every value is public and permanent, so anyone can re-fetch round N forever and get the same answer.

2. Derivation. That randomness drives a deterministic price rule in fixed point — 18 decimals, integer arithmetic end to end, no floats anywhere. Given a Room's spec, round N's price is a pure function of public data. Two families ship on EVM: Drift (geometric Brownian motion, with the −σ²/2 martingale correction so a high-volatility Room doesn't silently trend upward) and Step. A Room's id is the hash of its own spec, so changing any parameter produces a different Room rather than an edited one. Nobody can alter a Room after opening it, including its creator.

3. Commitment and fraud proof. Verifying one beacon round on-chain costs about 657,000 gas, 97% of it a single pairing. Verifying every round would cost roughly 1,600 MON a day, so the chain does not verify — it commits. A poster stakes a bond and submits a Merkle root for a 20-round epoch. It sits pending through a challenge window. Anyone who re-derives the epoch from the public beacon and finds a value that does not follow proves it in ONE transaction — no bisection game, no bond of their own — and takes the poster's bond. Challenging costs nothing but gas, which makes catching a liar the cheapest way to profit and honesty the cheapest way to avoid loss.

4. The market. Parimutuel pools, like a tote: everyone backing up shares one pool, everyone backing down shares the other, winners split in proportion to stake. No counterparty, no house position, so the protocol is never on the hook. A 1% rake is published up front and credited — not sent — to the Room's creator, because a creator whose address reverts on receipt must not be able to freeze everyone else's settlement. Settlement takes two prices, the window's open and close, each proved to belong to a FINALISED epoch. Pending checkpoints are refused outright: paying out against a number the fraud proof might still overturn would make the fraud proof pointless.

LIVE ON MONAD TESTNET

Entropy   0x09A00a27Cac602e777681F3242f4c7eFe989D4a7
Registry  0xE583B914CF2d25fc278301b195aB090640b4eECA
Ladder    0x1fa152836d8a5E6a0E5db8E2E811089ceE26025d
Market    0xBa0614A04243d037A4e05F901eB30C75079d1c9D

50 Rooms are open. Two things have been demonstrated end to end, by separate addresses that passed nothing between them:

A liar lost their bond. A checkpoint was posted whose price at one round was wrong by a single unit — 10^-18 of a price, the smallest lie the encoding can express. A second address re-derived the epoch from the public beacon, found the value that does not follow, and proved it. Posted: 0xfbdb3101. Disproved, bond forfeited: 0x35b60b28.

A bettor was paid from a proven price. Two accounts staked opposite sides of a window; settlement was shown the open and close with Merkle paths into an epoch the ladder had finalised. No oracle was consulted. Settled: 0xb747af55. Winner paid: 0x533c173d — staked 0.02, received 0.0495, with 0.0005 rake credited to the creator. The contract's remaining balance is exactly the unwithdrawn rake and nothing else.

A full round trip costs about 1.72M gas, roughly 0.18 MON. Settlement itself is 133,118 — less than opening the market.

WHY MONAD

The beacon emits every 3 seconds, and a market that opens, locks, settles and pays inside that cadence needs blocks that keep up and fees that make per-round activity sane. Monad also bills the gas LIMIT rather than gas used, which changes how you deploy: we measured every call against a live node with eth_estimateGas and hardcoded per-step limits, after a blanket 2.5x estimate multiplier under-funded one call by 137,000 gas and killed three transactions in a single broadcast. That work is written up in the repo rather than hidden.

TRY IT YOURSELF — NO WALLET, NOTHING TO INSTALL

The app hands you the controls instead of asserting things at you, and a guided tour explains every part of the page.

- Open your own Room. Move a slider and watch the room id change under your hand — content-addressing you can see rather than read about.
- Call the next tick. A chart advancing live with the beacon. Guess up or down; the round you are guessing on has not been published yet, and the panel enforces that rather than claiming it. Your hit rate settles on 50% and no reading of the chart moves it.
- Try to rig it. Pick any round in a finalised epoch, set the price to whatever you like, and ask the contract to accept it. The call is Ladder.provenClose — the same call the market makes before it pays anybody out. It is a view, so it is free and needs no wallet, and the Merkle root it checks lives in storage where no argument you supply can reach it. The honest value is accepted. Change it by one unit and it is refused exactly as firmly as if you had doubled it.

The chart itself is derived in your browser with ZERO calls to the blockchain — the page counts its own RPC traffic on screen to prove it. If Monad were unreachable, every price would still be correct.

ENGINEERING

This is the third implementation of one frozen specification. A Rust reference came first, and the Solidity is checked bit-for-bit against its vectors across 20,000 derivation rounds in both families. 112 tests pass. Gas is measured on a live node, not estimated.

Two protocol problems were found and reported rather than quietly patched: the specification's floor-freshness rule has its inequality backwards, which makes a stale floor weaken the fairness rules instead of tightening them; and removing the bisection game also removed the forced disclosure that made disproofs constructible, so posting now requires publishing the leaves.

KNOWN LIMITS, STATED PLAINLY

Two of eight families ship on EVM. There is no fee router — the rake goes entirely to the creator. Nothing runs unattended: one Room has a finalised epoch and one settled market, every post and settlement so far was a command somebody typed, and the frontend reports that rather than hiding it. One market, two accounts, five hundredths of a MON. The mechanism is proven; the volume is nothing.
```

---

## GitHub

```
https://github.com/crackedstudio/croom-monad
```

**The repository is currently PRIVATE.** A judge opening that link gets a 404.

---

## Progress update

Status: **On track**

```
Croom is a protocol for markets whose prices come from a public randomness beacon instead of an oracle — nobody can rig a price, predict it, or see it early, including us.

WHAT IS LIVE ON MONAD TESTNET

Four contracts deployed, 50 Rooms open, and two things demonstrated end to end by separate addresses that passed nothing between them:

- A liar lost their bond. A checkpoint was posted whose price at one round was wrong by 10^-18 — the smallest lie the encoding can express. Another address re-derived the epoch from the public beacon, found the value that does not follow, and disproved it in one transaction. Bond forfeited.
- A bettor was paid from a proven price. Two accounts staked opposite sides of a window; settlement was shown the open and close with Merkle paths into a finalised epoch. No oracle consulted. Winner staked 0.02 and received 0.0495.

THIS WEEK

Made the app something a visitor operates rather than reads. Three panels, none needing a wallet: build your own Room and watch its id change as you move a slider; guess the next tick on a chart advancing live with the beacon, where the round you are guessing on provably has not been published yet; and set any price you like in a finalised epoch and ask the contract to accept it. That last one calls Ladder.provenClose — the same call the market makes before it pays out — so a refusal comes from the deployed contract, not a mock. Also added a guided tour and explainers for every element on the page.

Engineering: 112 tests passing, checked bit-for-bit against a Rust reference across 20,000 derivation rounds in both families. Gas measured against a live node rather than estimated, after learning the hard way that Monad bills the limit.

NEXT, BEFORE THE DEADLINE

Record the demo video. Make the repository public.

WHERE MENTOR INPUT WOULD HELP

Our honest remaining gap is that nothing runs unattended — one Room has a finalised epoch and one settled market, and every post, floor advance and settlement so far was a command somebody typed. A keeper bot is maybe a day of work. With one day left, is it better to ship a thin keeper so the system is visibly alive, or to leave it and be explicit in the submission that the mechanism is proven while the volume is nothing? We have been assuming the second is more credible than a bot that might fall over during judging, but would value a second opinion.

Separately: we found two problems in the protocol specification and reported them in the repo rather than quietly implementing around them — one is that the floor-freshness rule has its inequality backwards, so a stale floor weakens the fairness checks instead of tightening them. If there is a venue for that feedback beyond our own repo, point us at it.
```
