/**
 * Event handlers.
 *
 * Status transitions are the only subtle part. A checkpoint is Pending when posted and becomes
 * Final or Rejected later, and those are separate events — so each handler loads the row and
 * narrows it rather than writing a fresh one, which would drop the leaves and the poster.
 */
import {
  Ladder,
  Market,
  Registry,
  type Checkpoint,
  type Protocol,
  type Room,
  type Stake,
  type Market as MarketEntity,
} from "generated";

const PROTOCOL_ID = "croom";
const SIDES = ["Up", "Down"] as const;

const side = (n: number | bigint): string => SIDES[Number(n)] ?? `Unknown(${n})`;

/** The running totals row, created on first touch. */
async function protocol(context: { Protocol: { get: (id: string) => Promise<Protocol | undefined> } }): Promise<Protocol> {
  const existing = await context.Protocol.get(PROTOCOL_ID);
  return (
    existing ?? {
      id: PROTOCOL_ID,
      rooms: 0n,
      checkpoints: 0n,
      rejected: 0n,
      markets: 0n,
      settled: 0n,
      totalStaked: 0n,
    }
  );
}

const checkpointId = (roomId: string, epoch: bigint) => `${roomId}-${epoch}`;
const stakeId = (marketId: string, staker: string, s: string) => `${marketId}-${staker.toLowerCase()}-${s}`;

// ── Registry ─────────────────────────────────────────────────────────────────────────────────

Registry.RoomOpened.handler(async ({ event, context }) => {
  const room: Room = {
    id: event.params.roomId,
    creator: event.params.creator,
    spec: event.params.spec,
    openedAt: BigInt(event.block.number),
    openedTx: event.transaction.hash,
  };
  context.Room.set(room);

  const p = await protocol(context);
  context.Protocol.set({ ...p, rooms: p.rooms + 1n });
});

// ── Ladder ───────────────────────────────────────────────────────────────────────────────────

Ladder.CheckpointPosted.handler(async ({ event, context }) => {
  // The leaves arrive as tuples of (round, close, high, low). Stored as parallel arrays because
  // GraphQL has no tuple type and four aligned lists survive a schema migration better than a
  // JSON blob nobody can filter on.
  const leaves = event.params.leaves as readonly (readonly [bigint, bigint, bigint, bigint])[];

  const cp: Checkpoint = {
    id: checkpointId(event.params.roomId, event.params.epoch),
    room_id: event.params.roomId,
    epoch: event.params.epoch,
    poster: event.params.poster,
    merkleRoot: event.params.merkleRoot,
    deadlineRound: event.params.deadlineRound,
    status: "Pending",
    postedAt: BigInt(event.block.number),
    postedTx: event.transaction.hash,
    endPrice: undefined,
    rejectedBy: undefined,
    rejectedRound: undefined,
    rejectedReason: undefined,
    leafRounds: leaves.map((l) => l[0]),
    leafCloses: leaves.map((l) => l[1]),
    leafHighs: leaves.map((l) => l[2]),
    leafLows: leaves.map((l) => l[3]),
  };
  context.Checkpoint.set(cp);

  const p = await protocol(context);
  context.Protocol.set({ ...p, checkpoints: p.checkpoints + 1n });
});

Ladder.CheckpointFinalized.handler(async ({ event, context }) => {
  const id = checkpointId(event.params.roomId, event.params.epoch);
  const cp = await context.Checkpoint.get(id);
  if (!cp) return; // Posted before the indexed range; nothing to narrow.
  context.Checkpoint.set({ ...cp, status: "Final", endPrice: event.params.endPrice });
});

Ladder.CheckpointRejected.handler(async ({ event, context }) => {
  const id = checkpointId(event.params.roomId, event.params.epoch);
  const cp = await context.Checkpoint.get(id);
  if (!cp) return;
  context.Checkpoint.set({
    ...cp,
    status: "Rejected",
    rejectedBy: event.params.challenger,
    rejectedRound: event.params.round,
    rejectedReason: event.params.reason,
  });

  const p = await protocol(context);
  context.Protocol.set({ ...p, rejected: p.rejected + 1n });
});

// ── Market ───────────────────────────────────────────────────────────────────────────────────

Market.MarketOpened.handler(async ({ event, context }) => {
  const m: MarketEntity = {
    id: event.params.marketId,
    room_id: event.params.roomId,
    startRound: event.params.startRound,
    endRound: event.params.endRound,
    state: "Open",
    upTotal: 0n,
    downTotal: 0n,
    winner: undefined,
    startClose: undefined,
    endClose: undefined,
    rake: undefined,
    openedAt: BigInt(event.block.number),
  };
  context.Market.set(m);

  const p = await protocol(context);
  context.Protocol.set({ ...p, markets: p.markets + 1n });
});

Market.Staked.handler(async ({ event, context }) => {
  const s = side(event.params.side);
  const id = stakeId(event.params.marketId, event.params.staker, s);

  // One staker may add to the same side more than once; the contract accumulates, so this does too.
  const existing = await context.Stake.get(id);
  const stake: Stake = existing
    ? { ...existing, amount: existing.amount + event.params.amount }
    : {
        id,
        market_id: event.params.marketId,
        staker: event.params.staker,
        side: s,
        amount: event.params.amount,
        claimed: false,
        payout: undefined,
      };
  context.Stake.set(stake);

  const market = await context.Market.get(event.params.marketId);
  if (market) {
    context.Market.set({
      ...market,
      upTotal: s === "Up" ? market.upTotal + event.params.amount : market.upTotal,
      downTotal: s === "Down" ? market.downTotal + event.params.amount : market.downTotal,
    });
  }

  const p = await protocol(context);
  context.Protocol.set({ ...p, totalStaked: p.totalStaked + event.params.amount });
});

Market.Settled.handler(async ({ event, context }) => {
  const market = await context.Market.get(event.params.marketId);
  if (!market) return;
  context.Market.set({
    ...market,
    state: "Settled",
    winner: side(event.params.winner),
    startClose: event.params.startClose,
    endClose: event.params.endClose,
    rake: event.params.rake,
  });

  const p = await protocol(context);
  context.Protocol.set({ ...p, settled: p.settled + 1n });
});

Market.Claimed.handler(async ({ event, context }) => {
  // The event does not say which side won, and the loser cannot claim — so whichever side this
  // staker is on, that is the row to mark.
  for (const s of SIDES) {
    const id = stakeId(event.params.marketId, event.params.staker, s);
    const stake = await context.Stake.get(id);
    if (stake) context.Stake.set({ ...stake, claimed: true, payout: event.params.amount });
  }
});

Market.Voided.handler(async ({ event, context }) => {
  const market = await context.Market.get(event.params.marketId);
  if (!market) return;
  context.Market.set({ ...market, state: "Void" });
});
