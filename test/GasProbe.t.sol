// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Bn254} from "../src/probe/Bn254.sol";
import {GasProbe} from "../src/probe/GasProbe.sol";
import {Test, console} from "forge-std/Test.sol";

/// @notice Proves the probe's pairing inputs are genuinely valid before we spend testnet funds
/// measuring them. Gas printed here is **Ethereum** pricing — `forge` runs a stock EVM — so it is
/// a correctness check and a comparison baseline, never the number that goes in the gas table.
/// The Monad figure comes from `script/ProbePairing.s.sol` against testnet (step 1.4).
contract GasProbeTest is Test {
    GasProbe internal probe;

    function setUp() public {
        probe = new GasProbe();
    }

    /// @dev e(G1, G2) · e(-G1, G2) = 1. If the G2 generator constants were wrong this would return
    /// false, so this assertion is what validates them — no constant here is trusted from memory.
    function test_BalancedPairingIsOne() public {
        (, bool ok, bool result) = probe.probePairing(2, Bn254.balancedInput(2));
        assertTrue(ok, "precompile reverted");
        assertTrue(result, "pairing product is not one");
    }

    /// @dev An odd number of alternating pairs leaves one unmatched exponent, so the product is not
    /// one — and the precompile charges full price to tell us so. That is the whole hazard of a
    /// chain that bills on `gas_limit`: a wrong answer costs exactly what a right one does.
    function test_UnbalancedPairingIsNotOne() public {
        (, bool ok, bool result) = probe.probePairing(3, Bn254.balancedInput(3));
        assertTrue(ok, "precompile reverted");
        assertFalse(result, "pairing product should not be one");
    }

    function test_MalformedInputReverts() public {
        // Not a multiple of 192 bytes: the precompile rejects the whole call.
        (, bool ok,) = probe.probePairing(0, hex"deadbeef");
        assertFalse(ok, "precompile accepted a malformed input");
    }

    function test_PointNotOnCurveReverts() public {
        (, bool ok,) = probe.probePairing(1, Bn254.offCurveInput());
        assertFalse(ok, "precompile accepted a point that is not on the curve");
    }

    /// @notice Prints the Ethereum-priced slope for comparison against Monad's measured one.
    function test_PrintEthereumBaseline() public {
        console.log("k   innerGas (ETHEREUM pricing, not Monad)");
        for (uint256 k = 1; k <= 4; k++) {
            (uint256 innerGas,,) = probe.probePairing(k, Bn254.balancedInput(k));
            console.log(k, innerGas);
        }
    }
}
