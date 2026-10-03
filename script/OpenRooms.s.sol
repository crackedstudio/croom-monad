// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice **Gate 2** — opens 50 Rooms spanning both shipped families and the full range of every
/// permitted parameter, then prints their ids for the README.
///
/// Every Room's genesis sits well above the proven floor, so none of them could have been
/// parameterised against randomness that already exists.
contract OpenRooms is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;
    uint256 internal constant ROOM_COUNT = 50;

    function run() external {
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (msg.sender != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", msg.sender);
            revert("wrong deployer: pass --sender as well as --account");
        }

        Registry registry = Registry(vm.envAddress("REGISTRY"));
        uint64 floor = Entropy(address(registry.entropy())).provenFloor();
        // Far enough ahead that the floor cannot overtake it while the broadcast lands.
        uint64 genesis = floor + 20_000;

        console.log("registry:    ", address(registry));
        console.log("proven floor:", floor);
        console.log("genesis:     ", genesis);

        vm.startBroadcast();
        for (uint256 i = 0; i < ROOM_COUNT; i++) {
            registry.openRoom(specAt(i, genesis));
        }
        vm.stopBroadcast();

        console.log("rooms opened:", ROOM_COUNT);
    }

    /// @dev Spreads the 50 Rooms across both families and the whole permitted parameter space, so
    /// "50 Rooms" is evidence that the bounds admit a real range rather than fifty copies.
    function specAt(
        uint256 i,
        uint64 genesis
    ) public pure returns (RoomSpec.Spec memory s) {
        bool drift = i % 2 == 0;

        s.family = drift ? RoomSpec.FAMILY_DRIFT : RoomSpec.FAMILY_STEP;
        s.beacon = RoomSpec.BEACON_EVMNET;
        s.subTicks = uint8(1 + (i % 3)); // 1..3
        s.epochRounds = uint32(20 + (i % 5) * 245); // 20, 265, 510, 755, 1000
        s.genesisRound = genesis + uint64(i); // distinct, all far in the future
        s.initialPrice = int256(100e18) * int256(1 + (i % 10)); // 100 .. 1000
        s.decimals = uint8(2 + (i % 3));
        s.mathVersion = RoomSpec.MATH_VERSION;
        s.hashFn = RoomSpec.HASH_FN;

        if (drift) {
            // 1% to ~1000% a year, across the whole permitted band.
            s.param = int256(1e16) + int256(uint256(i)) * int256(2e17);
        } else {
            // A step from 0.1% to ~5% of the opening price.
            s.param = s.initialPrice / int256(20 + (i % 30) * 32);
        }
    }
}
