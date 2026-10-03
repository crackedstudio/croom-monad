// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {OpenRooms} from "../script/OpenRooms.s.sol";
import {Entropy} from "../src/Entropy.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Runs the Gate 2 script's parameter generator against a real Registry before any of it
/// is broadcast. Fifty transactions is an expensive place to discover that room 37 has a step
/// larger than its price.
contract OpenRoomsTest is Test {
    Entropy internal entropy;
    Registry internal registry;
    OpenRooms internal script;

    function setUp() public {
        entropy = new Entropy();
        registry = new Registry(entropy);
        script = new OpenRooms();

        string memory json = vm.readFile("test/fixtures/drand/rounds/1000.json");
        entropy.proveRound(1000, vm.parseJsonBytes(json, ".signature"));
    }

    function test_AllFiftySpecsAreOpenableAndDistinct() public {
        uint64 genesis = entropy.provenFloor() + 20_000;
        bytes32[] memory ids = new bytes32[](50);

        for (uint256 i = 0; i < 50; i++) {
            RoomSpec.Spec memory s = script.specAt(i, genesis);
            ids[i] = registry.openRoom(s);

            for (uint256 j = 0; j < i; j++) {
                assertTrue(ids[i] != ids[j], "two Rooms share an id");
            }
        }

        assertEq(registry.creatorOf(ids[49]), address(this), "last Room recorded");
    }

    /// @dev The spread is the point: fifty Rooms are evidence the bounds admit a real range, not
    /// evidence that one spec can be submitted fifty times.
    function test_TheSpreadCoversBothFamiliesAndTheParameterSpace() public view {
        uint64 genesis = 100_000;
        uint256 drift;
        int256 minSigma = type(int256).max;
        int256 maxSigma;
        uint8 maxSubTicks;
        uint32 minEpoch = type(uint32).max;
        uint32 maxEpoch;

        for (uint256 i = 0; i < 50; i++) {
            RoomSpec.Spec memory s = script.specAt(i, genesis);
            if (s.family == RoomSpec.FAMILY_DRIFT) {
                drift++;
                if (s.param < minSigma) minSigma = s.param;
                if (s.param > maxSigma) maxSigma = s.param;
            }
            if (s.subTicks > maxSubTicks) maxSubTicks = s.subTicks;
            if (s.epochRounds < minEpoch) minEpoch = s.epochRounds;
            if (s.epochRounds > maxEpoch) maxEpoch = s.epochRounds;
        }

        assertEq(drift, 25, "half Drift, half Step");
        assertEq(maxSubTicks, 3, "reaches the sub-tick ceiling");
        assertEq(minEpoch, 20, "reaches the epoch floor");
        assertGe(maxEpoch, 1000, "reaches most of the epoch range");
        assertLe(minSigma, int256(1e16), "reaches the volatility floor");
        assertGe(maxSigma, int256(9e18), "reaches most of the volatility range");
    }
}
