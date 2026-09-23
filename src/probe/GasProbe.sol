// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title GasProbe
/// @notice Measurement scaffolding for step 1.4. **Not part of the protocol** — this contract
/// exists to answer one question on Monad testnet before we design around the answer: what does a
/// BN254 pairing check actually cost here?
///
/// The docs say `225,000 + 170,000 / point` (docs/monad-facts.md §5), against Ethereum's
/// `45,000 + 34,000·k`. If that is right, the two-point check at the heart of drand verification
/// budgets near 565,000 gas — and on Monad we pay that on `gas_limit`, whether the transaction
/// succeeds or reverts. That number decides how often we can afford to verify a round, so it gets
/// measured rather than quoted.
contract GasProbe {
    /// @notice Emitted so that a testnet transaction receipt carries the measurement.
    /// @param pairs Number of (G1, G2) pairs in the input.
    /// @param innerGas Gas consumed by the `staticcall` to `0x08` alone.
    /// @param ok Whether the precompile returned rather than reverted.
    /// @param result Whether the pairing product equalled one.
    event PairingProbe(uint256 indexed pairs, uint256 innerGas, bool ok, bool result);

    /// @notice Calls `0x08` with `input` and reports what it cost.
    /// @dev The measurement brackets the `staticcall` itself in assembly. A high-level call would
    /// fold ABI decoding and memory allocation into the figure, and the point of this contract is a
    /// number we can put in a gas table without an asterisk.
    function probePairing(
        uint256 pairs,
        bytes calldata input
    ) external returns (uint256 innerGas, bool ok, bool result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, input.offset, input.length)
            mstore(0x40, add(ptr, add(input.length, 0x20)))

            let before := gas()
            ok := staticcall(gas(), 0x08, ptr, input.length, ptr, 0x20)
            innerGas := sub(before, gas())

            result := and(ok, eq(mload(ptr), 1))
        }
        emit PairingProbe(pairs, innerGas, ok, result);
    }

    /// @notice A transaction whose receipt `gasUsed` is the end-to-end cost of one pairing check.
    /// @dev `probePairing` reports the precompile in isolation; this reports what we would actually
    /// have to set as a gas limit. On a chain that charges the limit, the second number is the one
    /// that spends money.
    ///
    /// It is `view` because it writes nothing — but we still send a *transaction* to it when
    /// measuring, precisely so the receipt's `gasUsed` is an end-to-end figure. It emits no event,
    /// deliberately: a log would add several thousand gas to the number we are trying to read.
    function checkPairing(
        bytes calldata input
    ) external view returns (bool result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, input.offset, input.length)
            mstore(0x40, add(ptr, add(input.length, 0x20)))
            let ok := staticcall(gas(), 0x08, ptr, input.length, ptr, 0x20)
            result := and(ok, eq(mload(ptr), 1))
        }
    }
}
