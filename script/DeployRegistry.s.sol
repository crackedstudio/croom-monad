// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Deploys `Registry` against the already-deployed `Entropy`.
///
/// ```bash
/// make deploy-registry ENTROPY=0x...
/// ```
contract DeployRegistry is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (msg.sender != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", msg.sender);
            revert("wrong deployer: pass --sender as well as --account");
        }

        Entropy entropy = Entropy(vm.envAddress("ENTROPY"));
        require(entropy.provenFloor() > 0, "entropy floor is zero: prove a round first");

        vm.startBroadcast();
        Registry registry = new Registry(entropy);
        vm.stopBroadcast();

        console.log("Registry deployed:", address(registry));
        console.log("entropy:          ", address(entropy));
        console.log("proven floor:     ", entropy.provenFloor());
    }
}
