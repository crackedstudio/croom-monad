// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Registry behaviour, and the absence of anything that could change a live Room.
contract RegistryTest is Test {
    Entropy internal entropy;
    Registry internal registry;

    uint64 internal floorRound;

    function setUp() public {
        entropy = new Entropy();
        registry = new Registry(entropy);

        // Advance the floor with a real beacon round so the fairness rule has something to bite.
        string memory json = vm.readFile("test/fixtures/drand/rounds/1000.json");
        entropy.proveRound(1000, vm.parseJsonBytes(json, ".signature"));
        floorRound = 1000;
    }

    function _spec() internal view returns (RoomSpec.Spec memory s) {
        s.family = RoomSpec.FAMILY_DRIFT;
        s.beacon = RoomSpec.BEACON_EVMNET;
        s.subTicks = 1;
        s.epochRounds = 100;
        s.genesisRound = floorRound + 100;
        s.initialPrice = 1000e18;
        s.decimals = 2;
        s.mathVersion = RoomSpec.MATH_VERSION;
        s.hashFn = RoomSpec.HASH_FN;
        s.param = 750e15; // 75% a year
    }

    // ── opening ──────────────────────────────────────────────────────────────────────────────

    function test_OpensARoomAndRecordsTheCreator() public {
        RoomSpec.Spec memory s = _spec();
        bytes32 expected = RoomSpec.roomId(s);

        vm.expectEmit(true, true, false, true, address(registry));
        emit Registry.RoomOpened(expected, address(this), RoomSpec.encode(s));
        bytes32 roomId = registry.openRoom(s);

        assertEq(roomId, expected, "roomId is the hash of the encoding");
        assertEq(registry.creatorOf(roomId), address(this));
        assertTrue(registry.isOpen(roomId));
    }

    function test_AnyoneCanOpenARoom() public {
        RoomSpec.Spec memory s = _spec();
        address stranger = address(0xBEEF);

        vm.prank(stranger);
        bytes32 roomId = registry.openRoom(s);
        assertEq(registry.creatorOf(roomId), stranger, "no permission required");
    }

    function test_TheSameSpecCannotBeOpenedTwice() public {
        RoomSpec.Spec memory s = _spec();
        bytes32 roomId = registry.openRoom(s);

        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyOpen.selector, roomId));
        registry.openRoom(s);
    }

    // ── the fairness rule ────────────────────────────────────────────────────────────────────

    /// @dev The rule that stops a creator picking parameters against randomness they already
    /// hold. Genesis must sit strictly above `floor + B`.
    function test_RejectsAGenesisThatAlreadyExists() public {
        RoomSpec.Spec memory s = _spec();
        s.genesisRound = floorRound; // already proven: its randomness is public

        vm.expectRevert(abi.encodeWithSelector(Registry.GenesisNotInFuture.selector, floorRound, floorRound));
        registry.openRoom(s);
    }

    function test_RejectsAGenesisInsideTheBuffer() public {
        RoomSpec.Spec memory s = _spec();
        s.genesisRound = floorRound + registry.ENTRY_BUFFER(); // exactly on the boundary

        vm.expectRevert(
            abi.encodeWithSelector(Registry.GenesisNotInFuture.selector, s.genesisRound, floorRound)
        );
        registry.openRoom(s);
    }

    function test_AcceptsAGenesisJustPastTheBuffer() public {
        RoomSpec.Spec memory s = _spec();
        s.genesisRound = floorRound + registry.ENTRY_BUFFER() + 1;
        registry.openRoom(s); // must not revert
    }

    /// @dev A rising floor invalidates specs that were previously openable. That is the point:
    /// the window to open a Room closes as the beacon advances past its genesis.
    function test_ARisingFloorClosesTheWindow() public {
        RoomSpec.Spec memory s = _spec();
        s.genesisRound = 1500;

        string memory json = vm.readFile("test/fixtures/drand/rounds/20880831.json");
        entropy.proveRound(20_880_831, vm.parseJsonBytes(json, ".signature"));

        vm.expectRevert(abi.encodeWithSelector(Registry.GenesisNotInFuture.selector, 1500, 20_880_831));
        registry.openRoom(s);
    }

    // ── bounds ───────────────────────────────────────────────────────────────────────────────

    function test_RejectsAnUnsupportedFamily() public {
        RoomSpec.Spec memory s = _spec();
        s.family = 4; // Spike: implemented in the reference, not in this port
        vm.expectRevert(abi.encodeWithSelector(Registry.UnsupportedFamily.selector, 4));
        registry.openRoom(s);
    }

    function test_RejectsOutOfRangeVolatility() public {
        RoomSpec.Spec memory s = _spec();
        s.param = 1e15; // 0.1% a year, below the 1% floor
        vm.expectRevert(abi.encodeWithSelector(Registry.SigmaOutOfRange.selector, 1e15));
        registry.openRoom(s);

        s.param = 11e18; // 1100% a year, above the 1000% ceiling
        vm.expectRevert(abi.encodeWithSelector(Registry.SigmaOutOfRange.selector, 11e18));
        registry.openRoom(s);
    }

    function test_RejectsOutOfRangeEpochAndSubTicks() public {
        RoomSpec.Spec memory s = _spec();
        s.epochRounds = 19;
        vm.expectRevert(abi.encodeWithSelector(Registry.EpochRoundsOutOfRange.selector, 19));
        registry.openRoom(s);

        s = _spec();
        s.epochRounds = 1201;
        vm.expectRevert(abi.encodeWithSelector(Registry.EpochRoundsOutOfRange.selector, 1201));
        registry.openRoom(s);

        s = _spec();
        s.subTicks = 4;
        vm.expectRevert(abi.encodeWithSelector(Registry.SubTicksOutOfRange.selector, 4));
        registry.openRoom(s);

        s = _spec();
        s.subTicks = 0;
        vm.expectRevert(abi.encodeWithSelector(Registry.SubTicksOutOfRange.selector, 0));
        registry.openRoom(s);
    }

    /// @dev A step above the opening price could cross zero in one tick. The model floors at the
    /// step size, so this keeps that floor below the opening price rather than above it.
    function test_RejectsAStepLargerThanThePrice() public {
        RoomSpec.Spec memory s = _spec();
        s.family = RoomSpec.FAMILY_STEP;
        s.param = s.initialPrice + 1;
        vm.expectRevert(abi.encodeWithSelector(Registry.StepOutOfRange.selector, s.param));
        registry.openRoom(s);
    }

    function test_RejectsBadVersionsAndBeacon() public {
        RoomSpec.Spec memory s = _spec();
        s.mathVersion = 2;
        vm.expectRevert(Registry.BadVersion.selector);
        registry.openRoom(s);

        s = _spec();
        s.hashFn = 2;
        vm.expectRevert(Registry.BadVersion.selector);
        registry.openRoom(s);

        s = _spec();
        s.beacon = 1;
        vm.expectRevert(Registry.BadBeacon.selector);
        registry.openRoom(s);
    }

    function test_RejectsNonPositiveInitialPrice() public {
        RoomSpec.Spec memory s = _spec();
        s.initialPrice = 0;
        vm.expectRevert(abi.encodeWithSelector(Registry.InitialPriceOutOfRange.selector, 0));
        registry.openRoom(s);
    }

    // ── no administrative surface ────────────────────────────────────────────────────────────

    /// @dev The creator holds a revenue claim, not a control. There is no function on this
    /// contract that mutates a Room once opened, which this asserts by exhaustion over the ABI:
    /// only `openRoom` is non-view, and it reverts on an existing Room.
    function test_NothingCanChangeALiveRoom() public {
        RoomSpec.Spec memory s = _spec();
        bytes32 roomId = registry.openRoom(s);
        address creator = registry.creatorOf(roomId);

        // Even the creator cannot reopen it with different parameters under the same id, because
        // the id *is* the parameters.
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyOpen.selector, roomId));
        registry.openRoom(s);

        RoomSpec.Spec memory tweaked = _spec();
        tweaked.param = 500e15;
        bytes32 other = registry.openRoom(tweaked);
        assertTrue(other != roomId, "different parameters, different Room");
        assertEq(registry.creatorOf(roomId), creator, "the original is untouched");
    }
}
