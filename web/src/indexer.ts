/**
 * The Envio indexer, with the log-paging path kept as a fallback.
 *
 * Reading Room history from logs meant paging `eth_getLogs` 100 blocks at a time — Monad's cap —
 * from the Registry's deployment at block 68,240,012. The head is past 70,700,000, so a Room
 * opened today sat roughly twenty-five thousand sequential requests away. It only worked because
 * the first fifty Rooms were opened within a few blocks of each other and the loop could stop
 * early, which is a property of the demo data rather than of the protocol.
 *
 * The fallback is not politeness. If the indexer is unreachable the page must still work, because
 * the whole argument of this project is that you do not have to trust an intermediary — and an
 * indexer is an intermediary. So the chart never depends on it, and the page says which path it
 * took rather than quietly looking the same either way.
 */
import type { Address, Hex } from "viem";

declare const __CROOM_INDEXER__: string;

export const INDEXER_URL = typeof __CROOM_INDEXER__ === "string" ? __CROOM_INDEXER__ : "";

export interface IndexedRoom {
  roomId: Hex;
  creator: Address;
  spec: Hex;
}

/** How the Rooms on screen were obtained, so the page can report it honestly. */
export interface Provenance {
  source: "indexer" | "logs";
  ms: number;
  requests: number;
  note: string;
}

const ROOMS_QUERY = `query Rooms($limit: Int!) {
  Room(limit: $limit, order_by: { openedAt: asc }) {
    id
    creator
    spec
  }
}`;

const STATS_QUERY = `query Stats {
  Protocol(limit: 1) { rooms checkpoints rejected markets settled totalStaked }
  chain_metadata { chain_id latest_processed_block block_height }
}`;

async function gql<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(INDEXER_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
    signal: AbortSignal.timeout(8_000),
  });
  if (!res.ok) throw new Error(`indexer returned ${res.status}`);
  const body = (await res.json()) as { data?: T; errors?: { message: string }[] };
  if (body.errors?.length) throw new Error(body.errors[0]!.message);
  if (!body.data) throw new Error("indexer returned no data");
  return body.data;
}

/** Rooms from the indexer, or `null` if it is not configured or not answering. */
export async function roomsFromIndexer(limit = 200): Promise<{ rooms: IndexedRoom[]; provenance: Provenance } | null> {
  if (!INDEXER_URL) return null;
  const started = performance.now();
  try {
    const data = await gql<{ Room: { id: Hex; creator: Address; spec: Hex }[] }>(ROOMS_QUERY, { limit });
    if (!data.Room?.length) return null; // Still backfilling: fall through rather than show nothing.
    return {
      rooms: data.Room.map((r) => ({ roomId: r.id, creator: r.creator, spec: r.spec })),
      provenance: {
        source: "indexer",
        ms: Math.round(performance.now() - started),
        requests: 1,
        note: "One query to an Envio indexer, instead of paging the chain 100 blocks at a time.",
      },
    };
  } catch {
    return null;
  }
}

export interface IndexerStats {
  rooms: bigint;
  checkpoints: bigint;
  rejected: bigint;
  markets: bigint;
  settled: bigint;
  totalStaked: bigint;
  /** How far behind the chain the indexer is, in blocks. */
  behind: number | null;
}

export async function indexerStats(): Promise<IndexerStats | null> {
  if (!INDEXER_URL) return null;
  try {
    const d = await gql<{
      Protocol: { rooms: string; checkpoints: string; rejected: string; markets: string; settled: string; totalStaked: string }[];
      chain_metadata: { chain_id: number; latest_processed_block: number | null; block_height: number | null }[];
    }>(STATS_QUERY);
    const p = d.Protocol?.[0];
    if (!p) return null;
    const meta = d.chain_metadata?.[0];
    const behind =
      meta?.block_height != null && meta?.latest_processed_block != null
        ? Math.max(0, meta.block_height - meta.latest_processed_block)
        : null;
    return {
      rooms: BigInt(p.rooms),
      checkpoints: BigInt(p.checkpoints),
      rejected: BigInt(p.rejected),
      markets: BigInt(p.markets),
      settled: BigInt(p.settled),
      totalStaked: BigInt(p.totalStaked),
      behind,
    };
  } catch {
    return null;
  }
}
