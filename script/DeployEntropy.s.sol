// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Step 2.5 — deploys `Entropy` and proves a live drand round against it, which is
/// **Gate 1**: a real evmnet round verified on Monad with the floor moved, on a public chain, with
/// a transaction hash to point at.
///
/// ```bash
/// make prove-round          # fetches the latest round and does both in one broadcast
/// ```
contract DeployEntropy is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address deployer = msg.sender;
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (deployer != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", deployer);
            if (deployer == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
                console.log("that is Foundry's default sender - add --sender");
            }
            revert("wrong deployer: pass --sender as well as --account");
        }

        uint64 round = uint64(vm.envUint("ROUND"));
        bytes memory signature = vm.envBytes("SIGNATURE");

        vm.startBroadcast();
        Entropy entropy = new Entropy();
        bytes32 randomness = entropy.proveRound(round, signature);
        vm.stopBroadcast();

        console.log("Entropy deployed:", address(entropy));
        console.log("round proven:    ", round);
        console.log("proven floor:    ", entropy.provenFloor());
        console.logBytes32(randomness);

        require(entropy.provenFloor() == round, "floor did not advance");

        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("dry run: nothing broadcast, no deployment record");
        }
    }
}
