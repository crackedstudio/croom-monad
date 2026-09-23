# Monad — facts, with sources

**Retrieved 2026-09-23.** Versions per the canonical
[current-facts](https://docs.monad.xyz/ai/current-facts) page: mainnet **`v0.16.1`**, testnet
**`v0.16.2`**, both revision **`MONAD_TEN`**. (The Network Information page still showed
`v0.15.2` / `MONAD_NINE`; where the two disagree, current-facts wins — it is the page Monad
maintains for exactly this purpose.)

Every figure here carries the URL it came from. Nothing in this file is written from memory, and
nothing that contradicts a live RPC answer survives — see [§7](#7-verification-against-the-live-network).

## 1. Networks

| | Mainnet | Testnet |
| --- | --- | --- |
| Chain ID | `143` | `10143` ⚠️ |
| Native token | MON | MON |
| Primary RPC | `https://rpc.monad.xyz` | `https://testnet-rpc.monad.xyz` |
| WebSocket | `wss://rpc.monad.xyz` | `wss://testnet-rpc.monad.xyz` |
| Explorer | `https://monadvision.com`, `https://monadscan.com` | `https://testnet.monadvision.com`, `https://testnet.monadscan.com` |
| App hub | — | `https://testnet.monad.xyz` |
| Faucet | — | `https://faucet.monad.xyz` |

Testnet rows are confirmed twice over: against the canonical
[current-facts](https://docs.monad.xyz/ai/current-facts) page, and against the RPC itself at
step 1.2. The Network Information page documents mainnet only, which is why an earlier draft of
this file had them marked unverified.

Mainnet RPC endpoints and their rate limits:

| URL | Provider | Rate limit |
| --- | --- | --- |
| `https://rpc.monad.xyz` | QuickNode | 25 rps |
| `https://rpc1.monad.xyz` | Alchemy | 15 rps |
| `https://rpc2.monad.xyz` | Goldsky Edge | 300 / 10s |
| `https://rpc3.monad.xyz` | Ankr | 300 / 10s |
| `https://rpc-mainnet.monadinfra.com` | Monad Foundation | 20 rps |

WebSocket is the same host on `wss://`.

Source: https://docs.monad.xyz/developer-essentials/network-information

## 2. Execution

| Property | Value |
| --- | --- |
| Block frequency | 300 ms |
| Speculative finality | 300 ms — 1 slot |
| Finalized | 2 blocks — 600 ms |
| Block gas limit | 150,000,000 |
| **Per-transaction gas limit** | **30,000,000** |
| Gas throughput | 500M gas/s |
| Design throughput | 10,000+ TPS |
| Verified (state root certainty) | 3 further blocks — 900 ms total |
| EVM fork | **Fusaka.** "All opcodes as of the Fusaka fork are supported" |
| Precompiles | All Ethereum precompiles as of Fusaka (`0x01`–`0x11`), plus P256 at `0x0100` (EIP-7951) and staking at `0x1000` |

Sources: https://docs.monad.xyz/developer-essentials/summary, https://docs.monad.xyz/ai/current-facts

**A 3-second beacon period against 600 ms finality leaves five blocks of margin per drand round.**
That is the arithmetic PLAN.md §2 rests on, and it now has a source.

## 3. Gas model

**Transactions are charged on `gas_limit`, not `gas_used`: `value + gas_bid × gas_limit`.** Stated
rationale is DoS prevention under asynchronous execution.

Other differences from Ethereum:

| | Monad | Ethereum |
| --- | --- | --- |
| Max contract size | 128 KB | 24 KB |
| Max init code size | 256 KB | 48 KB |
| Memory expansion | linear, `w / 2`, capped at 8 MB / tx (131,072 gas) | quadratic |
| Storage paging | slots grouped into pages of **128 consecutive slots**; first access to a page is cold, the rest of the page is warm | per-slot warming |
| Blob transactions | type 3 (EIP-4844) **not supported** | supported |
| EIP-7702 | delegated EOAs cannot drop below 10 MON; `CREATE`/`CREATE2` banned in delegated calls | no such constraint |
| Mempool | no global mempool; txs forwarded to the next few leaders | global |
| Historical state | full nodes do **not** serve arbitrary historic state | archive nodes do |

Source: https://docs.monad.xyz/developer-essentials/differences

## 4. Repriced opcodes

| Operation | Monad | Ethereum |
| --- | --- | --- |
| Cold account access (`BALANCE`, `EXTCODE*`, `CALL`, `DELEGATECALL`, `STATICCALL`, …) | 10,100 | 2,600 |
| `SLOAD`, first access to a page | 8,100 | 2,100 (cold slot) |
| `SLOAD`, warm | 100 | 100 |
| `SSTORE` base | 100 | — |
| `SSTORE` page load | 8,000 | — |
| `SSTORE` page write | 2,800 | — |
| `SSTORE` state growth | 17,000 per new high-water mark | 20,000 (new slot) |

`KECCAK256`, `TSTORE`/`TLOAD` and `MCOPY` are **not** listed as repriced.

Source: https://docs.monad.xyz/developer-essentials/opcode-pricing

## 5. Precompiles

| Address | Name | Monad gas | Ethereum |
| --- | --- | --- | --- |
| `0x01` | ecRecover | 6,000 | 3,000 |
| `0x02` | sha256 | 60 + 12·words | same |
| `0x03` | ripemd160 | 600 + 120·words | same |
| `0x04` | identity | 15 + 3·words | same |
| `0x05` | modexp | variable | variable |
| `0x06` | ecAdd (BN254) | 300 | 150 |
| `0x07` | ecMul (BN254) | **30,000** ✅ measured | 6,000 |
| `0x08` | **ecPairing (BN254)** | **225,000 + 170,000 / point** ✅ measured, `bench/precompiles.md` | 45,000 + 34,000·k |
| `0x09` | blake2f | rounds × 2 | rounds × 1 |
| `0x0a` | point_eval | 200,000 | 50,000 |
| `0x0b`–`0x11` | BLS12-381 (EIP-2537) | per EIP, `g1_add` 375, `g2_add` 600, `map_fp_to_g1` 5,500, `map_fp2_to_g2` 23,800 | same |
| `0x0100` | P256 verify (EIP-7951) | 6,900 | n/a |
| `0x1000` | staking | variable | n/a |
| `0x1001` | reserve balance | 100 | n/a |

Sources: https://docs.monad.xyz/developer-essentials/precompiles,
https://docs.monad.xyz/developer-essentials/opcode-pricing

## 6. RPC behaviour

| Tag | Meaning |
| --- | --- |
| `latest` | **proposed — speculative execution, no consensus vote yet** |
| `pending` | identical to `latest` |
| `safe` | backed by a supermajority vote |
| `finalized` | irreversible without a hard fork |

> "Any RPC response that includes data from a non-finalized block can change on a subsequent
> identical request."

- `eth_getLogs` block-range caps: QuickNode 100 blocks, Alchemy 1,000 blocks + 10,000 logs, Ankr 1,000 blocks, Monad Foundation 100 blocks.
- `eth_getTransactionByHash` returns `null` for mempool transactions.
- `eth_sendRawTransaction` accepts nonce gaps and insufficient balance — validation is deferred to execution.
- No `syncing` or `newPendingTransactions` subscriptions.
- `eth_maxPriorityFeePerGas` returns a hardcoded 2 gwei.
- `eth_feeHistory` repeats the latest `baseFeePerGas` twice.
- `debug_trace*` requires the options parameter; default tracer is `callTracer`.

Source: https://docs.monad.xyz/reference/rpc-differences

## 7. Verification against the live network

Checked 2026-09-23 against `https://testnet-rpc.monad.xyz`. Client reported **`Monad/0.16.2`** —
the docs' `v0.15.2` / `MONAD_NINE` refers to mainnet; testnet runs ahead.

| Claim | Result |
| --- | --- |
| Testnet chain ID is `10143` | ✅ `eth_chainId` → `10143` |
| Testnet RPC is `https://testnet-rpc.monad.xyz` | ✅ responds |
| Block cadence ≈ 300 ms | ✅ 1,000 blocks spanned 302 s → **302 ms/block** |
| `finalized` lags `latest` by 2 blocks / 600 ms | ✅ measured in a single batched request: latest `65001707`, safe `−1`, finalized `−2` |
| Testnet explorer resolves | ✅ `https://testnet.monadscan.com` → 200. `testnet.monadexplorer.com` → 403, `faucet.monad.xyz` → 429 (rate-limited, not down) |

Measured at the same time: base fee **100 gwei**, block gas limit **150,000,000**.

The lag must be read from a *batched* request. Three sequential `cast` calls put `finalized` numerically
*ahead* of `latest`, because the chain advanced ~3 blocks while the calls were in flight. At 300 ms,
any two RPC calls are already a different chain.

### Unsourced finding: timestamps have 1-second resolution

`block.timestamp` is in whole seconds while blocks are 300 ms apart, so **roughly three consecutive
blocks carry the same timestamp** — observed directly above, where `latest` and `safe` both read
`1790162486`.

This is not in the docs and it sharpens PLAN.md §3.1 from a design preference into a correctness
requirement. A timestamp on Monad cannot even distinguish two adjacent blocks, let alone estimate
which 3-second drand round is current. Every window, buffer and lock keys off the proven round
floor. There is no fallback reading of `block.timestamp` that would merely be *less precise* — there
is no correct reading of it at all.

## 8. What this changes for us

| Fact | Consequence | Step |
| --- | --- | --- |
| `ecPairing` = 225,000 + 170,000/point | A standard 2-point BLS check budgets at **≈ 565,000 gas**, roughly 5× Ethereum's 113,000. And we pay it on `gas_limit` whether the tx succeeds or reverts. Verifying every round is not viable; the proven-floor design — which verifies sparingly and treats the floor as a monotone claim — is load-bearing, not an elegance | 1.4, 2.3 |
| `ecMul` = 30,000 (5× Ethereum) | Audit `bls-solidity`'s hash-to-G1 for scalar multiplications before assuming its Ethereum gas profile carries over | 2.2 |
| `SLOAD` cold page = 8,100 | Page-contiguous hot state is worth ~8.1k per avoided page touch, not ~2.1k. This moves from a nicety to a first-order design constraint | 4.3 |
| `SSTORE` state growth = 17,000 | Every checkpoint that grows storage pays it. Epoch sizing must amortize it across enough ticks | 5.1 |
| Charged on `gas_limit` | A challenge that resolves cheaply still costs the full limit. Bonds sized against worst-case limit; bots never pad | 5.4, 6.5, 7.4 |
| `eth_getLogs` capped at 100–1,000 blocks | At 300 ms blocks, 100 blocks is **30 seconds** of history per call. A single day of backfill is 288,000 blocks — 2,880 calls at the QuickNode cap. Use the 1,000-block endpoint for backfill and page deliberately | 10.1 |
| `latest` is speculative | The indexer reads `finalized` only. A reorged tick in a chart is a broken conformance claim | 10.1 |
| Fusaka fork | Cancun opcodes (`TSTORE`/`TLOAD`/`MCOPY`) are available. solc 0.8.28 tops out at `cancun`, so that is the correct pin | 0.4 |
| No blob transactions | Epoch data goes in calldata or an event. Already assumed in PLAN.md §4 | 5.1 |
| **Per-transaction gas limit is 30,000,000** | A hard ceiling no amount of bidding raises. At 565k per pairing that is **at most ~53 verifications in one transaction**, and it bounds the terminal re-execution of a disputed tick and any single-transaction epoch operation. Stated only on the current-facts page — not in Developer Essentials | 5.1, 6.4, 6.5 |
| `block.timestamp` resolves to 1 s while blocks are 300 ms | ~3 blocks share a timestamp. Timestamps cannot identify a beacon round even approximately. Proven floor only, everywhere | 2.3, 5.2, 8.2 |
| Base fee 100 gwei, charged on `gas_limit` | A 565k-gas pairing verification costs ~0.0565 MON per attempt, successful or reverted. Bond sizing and faucet budget follow from this | 1.4, 5.4 |
| Block gas limit 150,000,000 | An epoch's terminal re-execution has generous headroom; epoch size is bounded by calldata and by `SSTORE` growth, not by block gas | 5.1, 6.5 |
| P256 at `0x0100`, 6,900 gas | Passkey-signed market entry is cheap here. Out of scope; one sentence in the writeup | 11.3 |
