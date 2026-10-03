// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Test} from "forge-std/Test.sol";

/// @notice `Entropy` against real beacon data and against every way a caller can get it wrong.
contract EntropyTest is Test {
    Entropy internal entropy;

    function setUp() public {
        entropy = new Entropy();
    }

    function _sig(
        string memory round
    ) internal view returns (bytes memory) {
        string memory json = vm.readFile(string.concat("test/fixtures/drand/rounds/", round, ".json"));
        return vm.parseJsonBytes(json, ".signature");
    }

    // ── the happy path ───────────────────────────────────────────────────────────────────────

    function test_ProvesRealRoundsAndAdvancesTheFloor() public {
        assertEq(entropy.provenFloor(), 0, "floor starts at zero");

        bytes32 randomness = entropy.proveRound(1, _sig("1"));
        assertEq(entropy.provenFloor(), 1);
        assertEq(randomness, sha256(_sig("1")), "randomness is sha256 of the signature");

        entropy.proveRound(1000, _sig("1000"));
        assertEq(entropy.provenFloor(), 1000, "the floor jumps; no intermediate rounds needed");

        entropy.proveRound(20_880_831, _sig("20880831"));
        assertEq(entropy.provenFloor(), 20_880_831);
    }

    /// @dev Unchained: any round verifies alone, so the floor can leap 20 million rounds in one
    /// call without walking a chain of predecessors.
    function test_VerifyRoundIsPureAndWorksBelowTheFloor() public {
        entropy.proveRound(20_880_831, _sig("20880831"));

        // The fraud proof's terminal step disputes an arbitrary historical round.
        bytes32 randomness = entropy.verifyRound(1, _sig("1"));
        assertEq(randomness, sha256(_sig("1")));
        assertEq(entropy.provenFloor(), 20_880_831, "verifyRound must not touch the floor");
    }

    function test_EmitsTheRandomnessForIndexers() public {
        vm.expectEmit(true, false, false, true, address(entropy));
        emit Entropy.RoundProven(1000, sha256(_sig("1000")));
        entropy.proveRound(1000, _sig("1000"));
    }

    // ── the floor is monotone ────────────────────────────────────────────────────────────────

    function test_FloorNeverGoesBackwards() public {
        entropy.proveRound(1000, _sig("1000"));

        vm.expectRevert(abi.encodeWithSelector(Entropy.FloorNotAdvanced.selector, 1, 1000));
        entropy.proveRound(1, _sig("1"));

        vm.expectRevert(abi.encodeWithSelector(Entropy.FloorNotAdvanced.selector, 1000, 1000));
        entropy.proveRound(1000, _sig("1000"));
    }

    // ── rejection paths ──────────────────────────────────────────────────────────────────────

    function test_RejectsRoundZero() public {
        vm.expectRevert(Entropy.RoundZero.selector);
        entropy.verifyRound(0, _sig("1"));
    }

    function test_RejectsWrongSignatureLength() public {
        vm.expectRevert(abi.encodeWithSelector(Entropy.InvalidSignatureLength.selector, 32));
        entropy.verifyRound(1, new bytes(32));
    }

    function test_RejectsOffCurvePoint() public {
        // x = 1, y = 3 is not on y^2 = x^3 + 3.
        bytes memory offCurve = abi.encodePacked(uint256(1), uint256(3));
        vm.expectRevert(Entropy.InvalidSignaturePoint.selector);
        entropy.verifyRound(1, offCurve);
    }

    function test_RejectsOutOfRangeCoordinates() public {
        uint256 fieldModulus =
            21_888_242_871_839_275_222_246_405_745_257_275_088_696_311_157_297_823_662_689_037_894_645_226_208_583;
        vm.expectRevert(Entropy.InvalidSignaturePoint.selector);
        entropy.verifyRound(1, abi.encodePacked(fieldModulus, uint256(2)));
    }

    /// @dev A valid signature is still bound to its round, or one proof would advance the floor
    /// arbitrarily far.
    function test_RejectsAValidSignatureReplayedAtAnotherRound() public {
        vm.expectRevert(Entropy.InvalidSignature.selector);
        entropy.verifyRound(1, _sig("1000"));

        vm.expectRevert(Entropy.InvalidSignature.selector);
        entropy.verifyRound(1000, _sig("1"));
    }

    function test_RejectsATamperedSignature() public {
        bytes memory sig = _sig("20880831");
        sig[63] = bytes1(uint8(sig[63]) ^ 0x01);

        // One flipped bit of y takes the point off the curve, so validation catches it before the
        // pairing ever runs.
        vm.expectRevert(Entropy.InvalidSignaturePoint.selector);
        entropy.verifyRound(20_880_831, sig);
    }

    // ── the expensive mistake this contract exists to avoid ──────────────────────────────────

    /// @dev The point of validating before calling `0x08`. A reverting pairing precompile consumes
    /// every gas unit forwarded to it, and on Monad the gas limit *is* the price — so without the
    /// check, submitting junk would cost a full transaction budget. With it, the rejection is
    /// ordinary. The bound is deliberately generous; the behaviour being asserted is three orders
    /// of magnitude, not a precise figure.
    function test_JunkSignatureRevertsCheaplyRatherThanBurningEverything() public view {
        bytes memory offCurve = abi.encodePacked(uint256(1), uint256(3));

        uint256 before = gasleft();
        try entropy.verifyRound(1, offCurve) {
            revert("should have reverted");
        } catch {}
        uint256 spent = before - gasleft();

        assertLt(spent, 100_000, "a junk signature must not cost a pairing, let alone the limit");
    }

    // ── no administrative surface ────────────────────────────────────────────────────────────

    /// @dev `provenFloor` is the only storage. If anyone adds mutable state, or moves the floor off
    /// slot 0 and out of its page, this fails rather than quietly costing another cold page touch.
    function test_StorageIsOneSlotAndTheFloorIsInIt() public {
        entropy.proveRound(1000, _sig("1000"));
        assertEq(uint256(vm.load(address(entropy), bytes32(0))), 1000, "floor lives in slot 0");

        for (uint256 slot = 1; slot < 8; slot++) {
            assertEq(uint256(vm.load(address(entropy), bytes32(slot))), 0, "unexpected storage");
        }
    }
}
