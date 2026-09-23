// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BLS} from "bls-solidity/libraries/BLS.sol";

/// @title BeaconVerifyReport
/// @notice Step 2.2/2.3. Verifies a **real drand evmnet round** on Monad and reports what each
/// stage costs, using the constructor-return trick so it needs no deployment and no funds.
///
/// ```bash
/// make verify-round ROUND=20880831
/// ```
///
/// This is the measurement that turns `bls-solidity` from a dependency we chose into one we have
/// evidence for. The split between hash-to-point and the pairing matters: `bench/precompiles.md`
/// pins the pairing at 565,000, but hash-to-point runs SVDW through the `modexp` precompile, whose
/// Monad cost the docs only describe as "variable".
contract BeaconVerifyReport {
    /// @dev drand evmnet's domain separation tag, from `EvmnetRegistry`. **Not** the DST that
    /// `BN254SignatureScheme` builds, which is derived from `block.chainid` and belongs to
    /// Randamu's own threshold network.
    string internal constant DST = "BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_";

    constructor(
        uint64 round,
        bytes memory signature
    ) {
        // evmnet public key, as served by the drand API. The struct orders each Fp2 coordinate
        // with the imaginary part at index 1, so the four API words land as x[1], x[0], y[1], y[0].
        BLS.PointG2 memory publicKey = BLS.PointG2(
            [
                0x0557ec32c2ad488e4d4f6008f89a346f18492092ccc0d594610de2732c8b808f,
                0x07e1d1d335df83fa98462005690372c643340060d205306a9aa8106b6bd0b382
            ],
            [
                0x297d3a4f9749b33eb2d904c9d9ebf17224150ddd7abd7567a9bec6c74480ee0b,
                0x0095685ae3a85ba243747b1b2f426049010f6b73a0cf1d389351d5aaaa1047f6
            ]
        );

        uint256 t0 = gasleft();
        // Unchained: the signed message is the round number alone. No predecessor, no chain walk.
        BLS.PointG1 memory message =
            BLS.hashToPoint(bytes(DST), abi.encodePacked(keccak256(abi.encodePacked(round))));
        uint256 gasHashToPoint = t0 - gasleft();

        uint256 t1 = gasleft();
        (bool pairingOk, bool callOk) = BLS.verifySingle(BLS.g1Unmarshal(signature), publicKey, message);
        uint256 gasPairing = t1 - gasleft();

        bytes memory out = abi.encode(pairingOk && callOk, gasHashToPoint, gasPairing, t0 - gasleft());
        assembly {
            return(add(out, 0x20), mload(out))
        }
    }
}
