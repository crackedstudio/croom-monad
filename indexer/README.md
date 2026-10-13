# Croom indexer — Envio HyperIndex

## Why this exists

The frontend read Room history straight from the chain's logs. Monad caps `eth_getLogs` at 100
blocks, the Registry went in at block 68,240,012, and the head is past 70,700,000 — so a Room
opened today sat roughly **twenty-five thousand sequential requests** away.

It worked at all only because the first fifty Rooms were opened within a few blocks of each other,
so the loop found them and stopped early. That is a property of the demo data, not of the protocol.
The README listed *"No indexer"* as a known limitation before this existed; this is that limitation
closed.

Measured on the live app: **7 RPC round-trips → 1 query.**

## What it indexes

| Entity | From |
| --- | --- |
| `Room` | `Registry.RoomOpened` |
| `Checkpoint` | `Ladder.CheckpointPosted` / `Finalized` / `Rejected` |
| `Market`, `Stake` | `Market.MarketOpened` / `Staked` / `Settled` / `Claimed` / `Voided` |
| `Protocol` | running totals, one row |

`Checkpoint` keeps the **published leaves** — every round's close, high and low. That is not
padding. A fraud proof is unconstructible without the leaves, which is why the contract emits them
and why `post` takes them rather than just a root. Serving them means a watcher who arrived after a
checkpoint was posted can still re-derive it and catch a lie.

Status is narrowed rather than rewritten: a checkpoint is `Pending` when posted and becomes `Final`
or `Rejected` on a later event, so each handler loads the row and edits it. Writing a fresh row
would drop the leaves and the poster.

## Deploy

```bash
npm install
npm run codegen     # types into .envio/, wired into the `envio` module
npx tsc --noEmit    # verifies the handlers against them
npm run dev         # local: indexer + GraphQL at http://localhost:8080
```

Written against **Envio v3**, whose shape differs from most of the examples online: the config key
is `chains` rather than `networks`, handlers register through `indexer.onEvent({contract, event})`
rather than `Contract.Event.handler()`, and everything imports from `envio` rather than from a
`generated` directory. `transaction.hash` also has to be asked for explicitly under
`field_selection` — without it the field exists in the types only as an error message explaining
how to request it, which is a nicer failure than most.

Hosted: connect the repo at [envio.dev](https://envio.dev), point it at `indexer/`, deploy. It
gives you a GraphQL endpoint.

## Point the app at it

```bash
CROOM_INDEXER="https://indexer.hyperindex.xyz/<id>/v1/graphql" make deploy-site
```

The endpoint is compiled into the bundle, which is fine — it serves public chain data.

**Leaving it unset is a supported configuration.** The app falls back to paging logs and says so on
screen. That fallback is load-bearing rather than polite: an indexer is an intermediary, and the
argument of this project is that you should not have to trust one. The chart never touches it —
prices are derived from the beacon in the browser. The indexer makes *history* cheap to read, not
truth cheaper to trust.
