// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BLS} from "bls-solidity/libraries/BLS.sol";

/// @title Entropy
/// @notice Verifies drand `evmnet` rounds and maintains the **proven round floor**: the highest
/// round for which a valid signature has been shown on this chain.
///
/// The floor is a proof that a round *exists*, never an estimate of when it existed. Nothing here
/// reads `block.timestamp`, and that is a correctness requirement rather than a preference: on
/// Monad a timestamp has one-second resolution while blocks are 300 ms apart, so roughly three
/// consecutive blocks share a timestamp and a timestamp cannot identify a 3-second beacon round
/// even approximately (`docs/monad-facts.md` §7).
///
/// No owner, no pause, no upgrade, no beacon parameter. The beacon is compiled in, so there is no
/// field an administrator could repoint. See `docs/decisions/0001-entropy.md`.
contract Entropy {
    /// @dev drand evmnet's domain separation tag, from the reference's `EvmnetRegistry`.
    /// **Not** the tag `BN254SignatureScheme` derives from `block.chainid`, which belongs to
    /// Randamu's own threshold network and would reject every genuine beacon
    /// (`docs/audits/bls-solidity.md`).
    bytes internal constant DST = "BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_";

    /// @notice evmnet's chain hash, confirmed against the drand API before anything hardcoded it.
    bytes32 public constant CHAIN_HASH = 0x04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3;

    /// @notice Seconds between beacon rounds. Informational: no logic here depends on elapsed time.
    uint64 public constant BEACON_PERIOD = 3;

    /// @notice The highest round proven to exist. Monotone, and the only storage this contract has.
    /// @dev Slot 0. A single slot is trivially inside one 128-slot page, so an advance pays one
    /// cold page touch and nothing more (`bench/storage-paging.md`).
    uint64 public provenFloor;

    event RoundProven(uint64 indexed round, bytes32 randomness);

    error RoundZero();
    error InvalidSignatureLength(uint256 length);
    error InvalidSignaturePoint();
    error InvalidSignature();
    error FloorNotAdvanced(uint64 round, uint64 floor);

    /// @notice evmnet's group public key.
    /// @dev The API serves 128 bytes as four words; `PointG2` holds each coordinate's imaginary
    /// part at index 1, so they land as `x[1], x[0], y[1], y[0]`. Asserted word-for-word against
    /// the beacon's own `/info` response in `test/BlsSolidity.t.sol`.
    function publicKey() public pure returns (BLS.PointG2 memory) {
        return BLS.PointG2(
            [
                0x0557ec32c2ad488e4d4f6008f89a346f18492092ccc0d594610de2732c8b808f,
                0x07e1d1d335df83fa98462005690372c643340060d205306a9aa8106b6bd0b382
            ],
            [
                0x297d3a4f9749b33eb2d904c9d9ebf17224150ddd7abd7567a9bec6c74480ee0b,
                0x0095685ae3a85ba243747b1b2f426049010f6b73a0cf1d389351d5aaaa1047f6
            ]
        );
    }

    /// @notice Verifies a round's signature and returns its randomness. Reads no storage and
    /// writes none, so it works for **any** round — including rounds far below the floor, which is
    /// what the fraud proof's terminal step needs.
    /// @dev The input point is validated **before** `0x08` is touched. A malformed or off-curve
    /// input makes the pairing precompile consume every gas unit forwarded to it, and on Monad the
    /// gas limit is the price — so an unvalidated junk signature costs the caller a whole
    /// transaction budget instead of a cheap revert (`bench/precompiles.md`). Validation is two
    /// comparisons and one curve equation.
    ///
    /// BN254 G1 has cofactor 1, so range plus curve membership is a *complete* validity check and
    /// no subgroup test is required.
    function verifyRound(
        uint64 round,
        bytes calldata signature
    ) public view returns (bytes32 randomness) {
        if (round == 0) revert RoundZero();
        if (signature.length != 64) revert InvalidSignatureLength(signature.length);

        BLS.PointG1 memory sigPoint = BLS.g1Unmarshal(signature);
        if (!BLS.isValidPointG1(sigPoint)) revert InvalidSignaturePoint();

        // Unchained scheme: the signed message is the round number alone, so a round verifies in
        // isolation with no predecessor. That is what makes a sparse floor possible.
        BLS.PointG1 memory message =
            BLS.hashToPoint(DST, abi.encodePacked(keccak256(abi.encodePacked(round))));

        (bool pairingOk, bool callOk) = BLS.verifySingle(sigPoint, publicKey(), message);
        if (!pairingOk || !callOk) revert InvalidSignature();

        // R_r = SHA-256(sigma_r) — drand's own definition, and the one the derivation consumes.
        // The single place SHA-256 appears; everything downstream is keccak.
        return sha256(signature);
    }

    /// @notice Verifies a round and raises the floor to it. Permissionless.
    /// @dev Reverts unless the floor actually advances. Paying ~620,000 gas to re-prove a round
    /// already below the floor is a mistake worth refusing rather than silently accepting, and on
    /// a chain that bills the gas limit the refusal costs the caller the same either way — so the
    /// check is for their benefit, not the contract's.
    function proveRound(
        uint64 round,
        bytes calldata signature
    ) external returns (bytes32 randomness) {
        uint64 floor = provenFloor;
        if (round <= floor) revert FloorNotAdvanced(round, floor);

        randomness = verifyRound(round, signature);
        provenFloor = round;

        emit RoundProven(round, randomness);
    }
}
