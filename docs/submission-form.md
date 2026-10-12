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

---

## Go-to-market and user acquisition (8,000 max)

```
WHO THE FIRST USERS ACTUALLY ARE

Not "traders" in general. Three specific groups, in the order we can reach them.

1. People who already bet on synthetic markets and have been burned by "provably fair." Crash games, dice sites and on-chain casinos all run on a seed the house generates and commits to. The commitment proves the house did not change its mind after seeing your bet; it proves nothing about how the seed was chosen. This audience is large, already transacting, and has a specific unmet complaint we answer exactly — our randomness is produced by a third party that does not know we exist, and anyone can recompute every price from public data.

2. Traders who want a market that is always open and depends on no asset. A Room never halts, never gets delisted, has no funding rate, no listing committee and no correlation to anything. For someone who wants pure price action at 3am on a Sunday, that is the product.

3. Builders who need a price primitive without an oracle. Anyone writing a perp, an option, a barrier payoff or a game needs a number nobody controls. Croom is that number, with a specification, a Rust reference, and now a Solidity implementation checked bit-for-bit against it. A Room's prices are identical on every chain that implements the spec, because the chain id is never hashed — so the same Room can settle on Monad and elsewhere with no bridge and no messaging.

THE WEDGE: THE PRODUCT IS ITS OWN PROOF

Most protocols have to argue for their trust properties in a blog post. We can hand someone the argument as an interaction that takes five seconds and needs no wallet.

Open the app, pick any price in a finalised epoch, change it to whatever you like, and ask the contract to accept it. It refuses — and the call doing the refusing is the same one the market makes before it pays anybody out. Change it by 10^-18 and it refuses just as firmly.

That is a shareable object, not a claim. It is the thing we lead with in every channel, because it converts scepticism into understanding faster than any amount of copy, and scepticism is the correct first reaction to "a casino you cannot rig."

HOW WE REACH THEM

Near term, concretely:

- Ship the "try to rig it" interaction as a standalone link and a 20-second clip. It is designed to be posted into exactly the threads where someone says provably fair systems are not. Crypto Twitter, r/gambling, Discord servers for existing synthetic-market products.
- Developer-first distribution. The specification, the Rust reference and the EVM implementation are public, with 20,000-round vectors anyone can check a fourth implementation against. A protocol that is trivially reimplementable gets reimplemented, and every implementation is a distribution channel we did not pay for.
- The Monad ecosystem. The 3-second beacon cadence only becomes a product on a chain that keeps up. We want to be the reason someone picks Monad for a markets product, which aligns our growth with the chain's.
- Creator supply. Opening a Room is permissionless and the creator earns the published 1% rake on every market in it. That is a real incentive to bring your own audience, and it is the only growth mechanism here that compounds without us.

WHAT WE WOULD MEASURE

Rooms opened by people who are not us; markets settled per week; the ratio of unique stakers to Rooms, which tells us whether creators are bringing anybody; and the number of independent checkpoint posters, because a protocol with one poster is a service with extra steps.

WHAT WE ARE NOT CLAIMING

We have no users yet. One market has settled, between two accounts we control, for five hundredths of a MON. We are not going to dress that up: what exists is a mechanism that provably works and a demonstration anybody can repeat, which is the honest position to start a go-to-market from rather than the end of one.

The first real test is not marketing. It is whether anyone other than us posts a checkpoint, because that is the moment the protocol stops needing us to run.
```

---

## Judge access instructions (optional, 8,000 max)

```
Nothing here needs a wallet, an account, test funds, or anything installed. Everything below is free to do and none of it can cost you anything.

START HERE — 60 SECONDS

Open the live product. A guided tour opens by itself and explains every part of the page; if you dismiss it, the "Show me around" button brings it back, and every "?" marker opens the same explanations on its own.

THE ONE THING TO TRY

Scroll to "Try to rig it."

1. Press "Ask Monad to accept this price" with the honest value. The contract returns it.
2. Press "+1 unit" — that is 10^-18, the smallest lie the encoding can express — and ask again. Refused, with the reason the chain gives: LeafNotCommitted.
3. Press "Crash it" and ask again. Refused exactly as firmly.

The call is Ladder.provenClose, which is the same call Market.settle makes before it pays anybody out. It is a view, so it costs nothing, and the Merkle root it checks against lives in the contract's storage where no argument you supply can reach it.

TWO MORE, IF YOU HAVE A MINUTE

"Call the next tick" — guess up or down on a chart advancing live with the beacon. The round you are guessing on has not been published yet and the panel enforces that rather than claiming it. Your hit rate settles on 50%.

"Open your own Room" — move a slider and watch the room id change under your hand. That is content-addressing: a different parameter is a different Room, not an edited one.

VERIFY US WITHOUT TRUSTING US

Round 21,173,055 was proven on Monad and the contract emitted this randomness:
0x0a53345742bad1bdfc2064519f95dfe41bd3044ca9f64d8ed4cbef0c27a6f3e4

Reproduce it from the public beacon, touching nothing of ours:

curl -s https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/21173055 | python3 -c 'import sys,json,hashlib; print(hashlib.sha256(bytes.fromhex(json.load(sys.stdin)["signature"])).hexdigest())'

THE TWO LIVE DEMONSTRATIONS, ON CHAIN

A liar lost their bond — posted 0xfbdb3101, disproved 0x35b60b28.
A bettor was paid from a proven price — settled 0xb747af55, claimed 0x533c173d.

Both on Monad testnet, between addresses that passed nothing between them.

CONTRACTS

Entropy   0x09A00a27Cac602e777681F3242f4c7eFe989D4a7
Registry  0xE583B914CF2d25fc278301b195aB090640b4eECA
Ladder    0x1fa152836d8a5E6a0E5db8E2E811089ceE26025d
Market    0xBa0614A04243d037A4e05F901eB30C75079d1c9D

FROM THE REPOSITORY

make print-market-values    reads the settled round back out of the chain, eth_call only, no key
forge test                  112 tests
CROOM_FULL_VECTORS=1 forge test   the full 20,000-round sweep against the Rust reference

ONE HONEST NOTE

Nothing runs unattended. One Room has a finalised epoch and one settled market; every checkpoint, floor advance and settlement so far was a command somebody typed. The app reports that plainly rather than hiding it, so a Room showing "no checkpoint posted yet" is the system being honest, not broken.
```
