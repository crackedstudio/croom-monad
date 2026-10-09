/**
 * The protocol layer, imported from the pinned reference SDK rather than reimplemented.
 *
 * `reference/croom-core/sdk/src/index.ts` re-exports `program.ts`, which pulls in
 * `@solana/web3.js` — so the modules are imported individually instead. What this app needs is
 * the *protocol*: derivation, specs, Merkle, and a drand client that verifies BN254 signatures in
 * the browser. The chain-specific half is ours (`chain.ts`).
 *
 * This is the third implementation of one frozen specification, and the one the chart renders
 * from. Rust produced the vectors, Solidity reproduces them on Monad, and this reproduces them
 * here — so the chart you see is computed in your browser, not fetched from us.
 */
export { DrandClient, EVMNET } from "../../reference/croom-core/sdk/src/drand.js";
export type { BeaconInfo, BeaconRound } from "../../reference/croom-core/sdk/src/drand.js";

export { Family, encodeSpec, decodeSpec, roomId, epochRange, epochOf } from "../../reference/croom-core/sdk/src/spec.js";
export type { RoomSpec, Params } from "../../reference/croom-core/sdk/src/spec.js";

export { Model, stateHash, encodeState, PRICE_MIN, PRICE_MAX } from "../../reference/croom-core/sdk/src/model.js";
export type { State } from "../../reference/croom-core/sdk/src/model.js";

export { deriveRound, derivePath } from "../../reference/croom-core/sdk/src/path.js";
export { deriveSeries, deriveEpoch } from "../../reference/croom-core/sdk/src/chart.js";
export { merkleRoot, leafHash, merkleProof } from "../../reference/croom-core/sdk/src/merkle.js";
export type { Leaf } from "../../reference/croom-core/sdk/src/merkle.js";
export type { Candle, Series } from "../../reference/croom-core/sdk/src/chart.js";

export { WAD } from "../../reference/croom-core/sdk/src/fixed.js";
