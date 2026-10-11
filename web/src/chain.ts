/**
 * The chain half. Read-only by default: the chart does not need it at all.
 *
 * This file exists so the page can *check* what it already computed, not so it can be told
 * anything. Every number shown on the chart is derived in the browser from the drand beacon; the
 * chain is consulted only to answer one question — does the commitment on Monad agree?
 */
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  fallback,
  http,
  parseAbi,
  type Address,
  type Hex,
} from "viem";

import { CHAIN_ID, DEPLOYMENTS, EXPLORER, RPC_URL } from "./deployments.js";

declare const __MONAD_TESTNET_RPC__: string;

/**
 * More than one endpoint, because on 11 October the primary stopped answering entirely — two days
 * before a deadline, which is exactly when it would. viem's `fallback` transport tries each in
 * turn, so the verification step degrades to "slower" rather than "broken".
 *
 * The chart does not use any of these. That is the point: an outage here costs you the ability to
 * *check* the chain, not the ability to compute the prices.
 */
export const RPC_URLS = [
  __MONAD_TESTNET_RPC__ || RPC_URL,
  "https://rpc.ankr.com/monad_testnet",
  "https://monad-testnet.drpc.org",
] as const;

export const monadTestnet = defineChain({
  id: CHAIN_ID,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [...RPC_URLS] } },
  blockExplorers: { default: { name: "Monadscan", url: EXPLORER } },
});

export const publicClient = createPublicClient({
  chain: monadTestnet,
  transport: fallback(RPC_URLS.map((url) => http(url, { timeout: 8_000, retryCount: 1 }))),
});

export const entropyAbi = parseAbi([
  "function provenFloor() view returns (uint64)",
  "function CHAIN_HASH() view returns (bytes32)",
  "event RoundProven(uint64 indexed round, bytes32 randomness)",
]);

export const registryAbi = parseAbi([
  "function creatorOf(bytes32) view returns (address)",
  "function isOpen(bytes32) view returns (bool)",
  "event RoomOpened(bytes32 indexed roomId, address indexed creator, bytes spec)",
]);

export const ladderAbi = parseAbi([
  "function bond() view returns (uint256)",
  "function challengeRounds() view returns (uint64)",
  "function roomState(bytes32) view returns (int128 finalPrice, uint64 nextEpoch)",
  "function checkpoints(bytes32, uint64) view returns (bytes32 prevStateHash, bytes32 endStateHash, bytes32 merkleRoot, address poster, uint64 deadlineRound, uint8 status, uint96 bond)",
]);

export const marketAbi = parseAbi([
  "function RAKE_BPS() view returns (uint256)",
  "function ENTRY_BUFFER() view returns (uint64)",
  "function books(bytes32) view returns (bytes32 roomId, uint64 startRound, uint64 endRound, uint128 upTotal, uint128 downTotal, uint128 payoutPool, uint8 state, uint8 winner)",
  "function marketId(bytes32, uint64, uint64) pure returns (bytes32)",
  "function enter(bytes32, uint8) payable",
  "function claim(bytes32)",
  "function stakeOf(bytes32, address, uint8) view returns (uint128)",
]);

export const addresses = {
  entropy: DEPLOYMENTS.Entropy.address as Address,
  registry: DEPLOYMENTS.Registry.address as Address,
  ladder: DEPLOYMENTS.Ladder.address as Address,
  market: (DEPLOYMENTS as Record<string, { address: string } | undefined>).Market?.address as
    | Address
    | undefined,
};

export const CHECKPOINT_STATUS = ["None", "Pending", "Final", "Rejected"] as const;

export async function provenFloor(): Promise<bigint> {
  return publicClient.readContract({
    address: addresses.entropy,
    abi: entropyAbi,
    functionName: "provenFloor",
  });
}

export interface OnChainCheckpoint {
  prevStateHash: Hex;
  endStateHash: Hex;
  merkleRoot: Hex;
  poster: Address;
  deadlineRound: bigint;
  status: (typeof CHECKPOINT_STATUS)[number];
  bond: bigint;
}

export async function checkpoint(roomId: Hex, epoch: bigint): Promise<OnChainCheckpoint | null> {
  const r = await publicClient.readContract({
    address: addresses.ladder,
    abi: ladderAbi,
    functionName: "checkpoints",
    args: [roomId, epoch],
  });
  const status = CHECKPOINT_STATUS[Number(r[5])] ?? "None";
  if (status === "None") return null;
  return {
    prevStateHash: r[0],
    endStateHash: r[1],
    merkleRoot: r[2],
    poster: r[3],
    deadlineRound: r[4],
    status,
    bond: r[6],
  };
}

/**
 * Rooms are read from logs, not storage: the registry keeps only the hash and emits the body.
 *
 * Monad's public RPC caps `eth_getLogs` at 100 blocks, and at 300 ms per block that is thirty
 * seconds of history per call — so a naive scan from genesis would be thousands of requests. The
 * deployment block is known, so the scan starts there and pages deliberately.
 */
export async function roomsOpened(
  fromBlock = BigInt(DEPLOYMENTS.Registry.block),
  pageSize = 100n,
): Promise<{ roomId: Hex; creator: Address; spec: Hex }[]> {
  const latest = await publicClient.getBlockNumber();
  const out: { roomId: Hex; creator: Address; spec: Hex }[] = [];

  for (let from = fromBlock; from <= latest; from += pageSize) {
    const to = from + pageSize - 1n > latest ? latest : from + pageSize - 1n;
    const logs = await publicClient.getContractEvents({
      address: addresses.registry,
      abi: registryAbi,
      eventName: "RoomOpened",
      fromBlock: from,
      toBlock: to,
    });
    for (const log of logs) {
      const a = log.args as { roomId?: Hex; creator?: Address; spec?: Hex };
      if (a.roomId && a.creator && a.spec) {
        out.push({ roomId: a.roomId, creator: a.creator, spec: a.spec });
      }
    }
    // The rooms were all opened within a few blocks of each other; once found, stop paging.
    if (out.length >= 50) break;
  }
  return out;
}

/** The browser wallet, requested only when the user actually wants to stake. */
export async function connect(): Promise<{ account: Address; write: ReturnType<typeof createWalletClient> }> {
  const injected = (globalThis as { ethereum?: unknown }).ethereum;
  if (!injected) throw new Error("No wallet found. Install a browser wallet to stake.");

  const write = createWalletClient({ chain: monadTestnet, transport: custom(injected as never) });
  const [account] = await write.requestAddresses();
  if (!account) throw new Error("No account authorised.");

  const current = await write.getChainId();
  if (current !== CHAIN_ID) {
    await write.switchChain({ id: CHAIN_ID }).catch(async () => {
      await write.addChain({ chain: monadTestnet });
      await write.switchChain({ id: CHAIN_ID });
    });
  }
  return { account, write };
}

export const txUrl = (hash: string) => `${EXPLORER}/tx/${hash}`;
export const addressUrl = (address: string) => `${EXPLORER}/address/${address}`;
