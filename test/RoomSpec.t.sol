// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RoomSpec} from "../src/RoomSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Spec encoding, `roomId` and `stateHash` against the reference's frozen vectors.
///
/// The vectors carry the canonical encoding as `encoded_hex`, so this compares bytes rather than
/// hashes first — when it fails, it says *which field* is wrong instead of only that the identity
/// does not match.
contract RoomSpecTest is Test {
    function _room(
        string memory name
    ) internal view returns (string memory) {
        return vm.readFile(string.concat("test/fixtures/vectors/rooms/", name, ".json"));
    }

    function _spec(
        string memory name
    ) internal view returns (RoomSpec.Spec memory s) {
        string memory json = _room(name);
        s.family = _familyOf(vm.parseJsonString(json, ".family"));
        s.beacon = uint8(vm.parseJsonUint(json, ".beacon"));
        s.subTicks = uint8(vm.parseJsonUint(json, ".subTicks"));
        s.epochRounds = uint32(vm.parseJsonUint(json, ".epochRounds"));
        s.genesisRound = uint64(vm.parseUint(vm.parseJsonString(json, ".genesisRound")));
        s.initialPrice = vm.parseInt(vm.parseJsonString(json, ".initialPrice"));
        s.decimals = uint8(vm.parseJsonUint(json, ".decimals"));
        s.mathVersion = uint8(vm.parseJsonUint(json, ".mathVersion"));
        s.hashFn = uint8(vm.parseJsonUint(json, ".hashFn"));
        s.param = vm.parseInt(vm.parseJsonString(json, ".param"));
    }

    /// @dev Memory structs are reference types in Solidity: `Spec memory b = a` copies the
    /// *pointer*, so mutating `b` mutates `a`. A test that tweaks a "copy" and compares against
    /// the original therefore compares the mutated struct with itself — and passes, which is worse
    /// than failing. Everything below copies fields explicitly.
    function _copy(
        RoomSpec.Spec memory s
    ) internal pure returns (RoomSpec.Spec memory c) {
        c.family = s.family;
        c.beacon = s.beacon;
        c.subTicks = s.subTicks;
        c.epochRounds = s.epochRounds;
        c.genesisRound = s.genesisRound;
        c.initialPrice = s.initialPrice;
        c.decimals = s.decimals;
        c.mathVersion = s.mathVersion;
        c.hashFn = s.hashFn;
        c.param = s.param;
    }

    function _familyOf(
        string memory name
    ) internal pure returns (uint8) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("drift")) return RoomSpec.FAMILY_DRIFT;
        if (h == keccak256("step")) return RoomSpec.FAMILY_STEP;
        revert(string.concat("unknown family: ", name));
    }

    function _check(
        string memory name
    ) internal view {
        string memory json = _room(name);
        RoomSpec.Spec memory s = _spec(name);

        bytes memory expected = vm.parseJsonBytes(json, ".encoded");
        assertEq(RoomSpec.encode(s), expected, string.concat(name, ": canonical encoding"));
        assertEq(expected.length, 51, string.concat(name, ": 51 bytes"));

        assertEq(RoomSpec.roomId(s), vm.parseJsonBytes32(json, ".roomId"), string.concat(name, ": roomId"));

        RoomSpec.State memory initial = RoomSpec.State({
            price: s.initialPrice,
            level: uint8(vm.parseJsonUint(json, ".initialLevel")),
            lo: vm.parseInt(vm.parseJsonString(json, ".initialLo")),
            hi: vm.parseInt(vm.parseJsonString(json, ".initialHi"))
        });
        assertEq(
            RoomSpec.stateHash(s.family, initial),
            vm.parseJsonBytes32(json, ".initialStateHash"),
            string.concat(name, ": initial stateHash")
        );
    }

    function test_DriftRoomMatchesTheReference() public view {
        _check("drift");
    }

    function test_StepRoomMatchesTheReference() public view {
        _check("step");
    }

    /// @dev Identity is content. Any field, including one the family ignores, gives a new Room.
    function test_EveryFieldChangesTheRoomId() public view {
        RoomSpec.Spec memory base = _spec("drift");
        bytes32 id = RoomSpec.roomId(base);

        RoomSpec.Spec memory m = _copy(base);
        m.subTicks = base.subTicks + 1;
        assertTrue(RoomSpec.roomId(m) != id, "subTicks");

        m = _copy(base);
        m.epochRounds = base.epochRounds + 1;
        assertTrue(RoomSpec.roomId(m) != id, "epochRounds");

        m = _copy(base);
        m.genesisRound = base.genesisRound + 1;
        assertTrue(RoomSpec.roomId(m) != id, "genesisRound");

        m = _copy(base);
        m.initialPrice = base.initialPrice + 1;
        assertTrue(RoomSpec.roomId(m) != id, "initialPrice");

        m = _copy(base);
        m.param = base.param + 1;
        assertTrue(RoomSpec.roomId(m) != id, "param");

        // `decimals` is display-only and changes nothing about the price path — and still must
        // change the identity, or two Rooms that render differently would share a commitment.
        m = _copy(base);
        m.decimals = base.decimals + 1;
        assertTrue(RoomSpec.roomId(m) != id, "decimals");

        m = _copy(base);
        m.family = RoomSpec.FAMILY_STEP;
        assertTrue(RoomSpec.roomId(m) != id, "family");
    }

    function test_RejectsAnUnsupportedFamily() public {
        RoomSpec.Spec memory s = _spec("drift");
        s.family = 4; // Spike: in the reference, not in this port
        vm.expectRevert(abi.encodeWithSelector(RoomSpec.UnsupportedFamily.selector, 4));
        this.encodeExternal(s);
    }

    function encodeExternal(
        RoomSpec.Spec memory s
    ) external pure returns (bytes memory) {
        return RoomSpec.encode(s);
    }

    /// @dev Negative prices cannot occur in a well-formed Room, but the encoder must still produce
    /// the reference's two's complement rather than reverting or truncating, because the fraud
    /// proof may be asked to hash a state a liar proposed.
    function test_EncodesNegativeValuesAsTwosComplement() public view {
        RoomSpec.State memory st = RoomSpec.State({price: -1, level: 0, lo: 0, hi: 0});
        bytes memory encoded = RoomSpec.encodeState(RoomSpec.FAMILY_DRIFT, st);
        assertEq(encoded.length, 50, "50 bytes");
        // family byte, then 16 bytes of 0xff for -1.
        assertEq(uint8(encoded[0]), 0);
        for (uint256 i = 1; i <= 16; i++) {
            assertEq(uint8(encoded[i]), 0xff, "two's complement of -1");
        }
    }
}
