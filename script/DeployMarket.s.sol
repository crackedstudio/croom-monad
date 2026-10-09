// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ladder} from "../src/Ladder.sol";
import {Market} from "../src/Market.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Deploys `Market` against the live `Ladder`.
///
/// ```bash
/// make deploy-market LADDER=0x...
/// ```
contract DeployMarket is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (msg.sender != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", msg.sender);
            revert("wrong deployer: pass --sender as well as --account");
        }

        Ladder ladder = Ladder(vm.envAddress("LADDER"));

        vm.startBroadcast();
        Market market = new Market(ladder);
        vm.stopBroadcast();

        console.log("Market deployed:", address(market));
        console.log("ladder:         ", address(ladder));
        console.log("rake (bps):     ", market.RAKE_BPS());
        console.log("entry buffer:   ", market.ENTRY_BUFFER());
    }
}
