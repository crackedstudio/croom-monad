// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Conformance of the derivation against `croom-core`'s frozen per-round vectors.
///
/// Each record carries the beacon value going in and the complete state coming out — close, high,
/// low and the state hash. Matching the state hash as well as the prices means the state encoding
/// is checked at the same time, which is what the ladder actually commits to.
///
/// Defaults to 2,000 rounds per family so the suite stays fast enough that it gets run. Set
/// `CROOM_FULL_VECTORS=1` for all 10,000 — the nightly sweep does.
contract TickTest is Test {
    uint256 internal constant RECORD = 153;
    uint256 internal constant HEADER = 12;
    bytes8 internal constant MAGIC = 0x43524f4f4d524e44; // "CROOMRND"

    function _spec(
        string memory name
    ) internal view returns (RoomSpec.Spec memory s) {
        string memory json = vm.readFile(string.concat("test/fixtures/vectors/rooms/", name, ".json"));
        bytes32 family = keccak256(bytes(vm.parseJsonString(json, ".family")));
        s.family = family == keccak256("drift") ? RoomSpec.FAMILY_DRIFT : RoomSpec.FAMILY_STEP;
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

    function _run(
        string memory name
    ) internal view {
        RoomSpec.Spec memory spec = _spec(name);
        Tick.Model memory model = Tick.compile(spec);

        bytes memory data = vm.readFileBinary(string.concat("test/fixtures/vectors/rounds/", name, ".bin"));
        require(bytes8(_word(data, 0)) == MAGIC, "bad rounds magic");
        uint256 count = uint32(uint256(_word(data, 8) >> 224));
        require(data.length == HEADER + count * RECORD, "rounds length disagrees with count");
        require(count > 0, "no rounds");

        uint256 limit = vm.envOr("CROOM_FULL_VECTORS", uint256(0)) == 1 ? count : 2000;
        if (limit > count) limit = count;

        int256 price = spec.initialPrice;
        for (uint256 i = 0; i < limit; i++) {
            price = _checkRound(model, spec.family, data, HEADER + i * RECORD, price, i);
        }
    }

    /// @dev One round, in its own frame. Inlining this hits "stack too deep": the expected record
    /// has seven fields and the computed state three more, past what the legacy codegen can hold.
    function _checkRound(
        Tick.Model memory model,
        uint8 family,
        bytes memory data,
        uint256 at,
        int256 price,
        uint256 i
    ) private view returns (int256) {
        (int256 close, int256 high, int256 low) = Tick.deriveRound(model, price, _word(data, at + 8));

        // Compare first, build the message only when it is about to be used. `_why` concatenates
        // a string, and EVM memory never frees — eagerly building four messages per round across
        // 10,000 rounds exhausts the runner's memory limit before the suite finishes.
        if (close != _i128(data, at + 40)) assertEq(close, _i128(data, at + 40), _why(i, "close"));
        if (high != _i128(data, at + 56)) assertEq(high, _i128(data, at + 56), _why(i, "high"));
        if (low != _i128(data, at + 72)) assertEq(low, _i128(data, at + 72), _why(i, "low"));

        RoomSpec.State memory state = RoomSpec.State({
            price: close, level: uint8(data[at + 88]), lo: _i128(data, at + 89), hi: _i128(data, at + 105)
        });
        bytes32 got = RoomSpec.stateHash(family, state);
        if (got != _word(data, at + 121)) assertEq(got, _word(data, at + 121), _why(i, "stateHash"));

        return close;
    }

    function test_DriftMatchesTheReference() public view {
        _run("drift");
    }

    function test_StepMatchesTheReference() public view {
        _run("step");
    }

    /// @dev A Room with two sub-ticks has each sub-tick spanning half a round, so its per-sub-tick
    /// volatility is lower. `k` divides inside `dt`, and getting that backwards would still
    /// produce a plausible chart.
    function test_SubTicksDivideTheTimeStep() public view {
        RoomSpec.Spec memory one = _spec("drift");
        assertEq(one.subTicks, 1, "drift room has k = 1");

        RoomSpec.Spec memory two = _copy(one);
        two.subTicks = 2;

        assertLt(Tick.compile(two).sigmaT, Tick.compile(one).sigmaT, "more sub-ticks, less volatility each");
    }

    /// @dev The domain prefix, the sub-tick index and the stream byte all separate the draws. If
    /// any were dropped, two different draws would collide and the price would stop being random
    /// in the way the model assumes.
    function test_EveryInputSeparatesTheDraw() public pure {
        bytes32 r = keccak256("r");
        bytes32 room = keccak256("room");

        int256 base = Tick.uniformWad(r, room, 0, Tick.STREAM_DIFFUSION);
        assertTrue(base != Tick.uniformWad(r, room, 1, Tick.STREAM_DIFFUSION), "sub-tick");
        assertTrue(base != Tick.uniformWad(r, room, 0, Tick.STREAM_REGIME), "stream");
        assertTrue(base != Tick.uniformWad(keccak256("r2"), room, 0, Tick.STREAM_DIFFUSION), "beacon");
        assertTrue(base != Tick.uniformWad(r, keccak256("other"), 0, Tick.STREAM_DIFFUSION), "room");
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

    function _i128(
        bytes memory b,
        uint256 offset
    ) private pure returns (int256) {
        // 16 bytes, big-endian two's complement: take the top half of the word and sign-extend.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(int128(uint128(bytes16(_word(b, offset)))));
    }

    function _word(
        bytes memory b,
        uint256 offset
    ) private pure returns (bytes32 w) {
        assembly ("memory-safe") {
            w := mload(add(add(b, 0x20), offset))
        }
    }

    function _why(
        uint256 i,
        string memory field
    ) private pure returns (string memory) {
        return string.concat("round index ", vm.toString(i), ": ", field);
    }
}
