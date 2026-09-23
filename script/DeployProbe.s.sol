// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {GasProbe} from "../src/probe/GasProbe.sol";
import {StoragePageProbe} from "../src/probe/StoragePageProbe.sol";
import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Step 1.3 — the first real deployment, and the vehicle for re-measuring `0x08` through
/// an actual transaction rather than `eth_call`.
///
/// ```bash
/// forge script script/DeployProbe.s.sol --rpc-url monad_testnet \
///   --account croom-deployer --broadcast
/// ```
///
/// Writes `deployments/<chainid>/GasProbe.json`. The README's address table is generated from
/// those files, never hand-typed.
contract DeployProbe is Script {
    /// @dev The `croom-deployer` keystore, confirmed by `make whoami-deployer` and holding the
    /// faucet's 5 MON. Deploying from anything else is a mistake worth catching before it costs a
    /// transaction — there are four keystores on this machine and a keystore file does not carry
    /// its address in the clear, so the only way to know is to ask it.
    ///
    /// This constant was briefly wrong: it held the `to` address of the faucet transaction, which
    /// is the faucet *contract* rather than the recipient. The assertion is what surfaced that.
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address deployer = msg.sender;
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);

        if (deployer != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", deployer);
            // 0x1804c8AB... is Foundry's default sender. Seeing it here means --sender was
            // omitted: --account alone is consulted only at broadcast, so the simulation ran
            // as nobody in particular and this check fired before any password prompt.
            if (deployer == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
                console.log("that is Foundry's default sender - add --sender");
            }
            revert("wrong deployer: pass --sender as well as --account, or set EXPECTED_DEPLOYER");
        }
        require(deployer.balance > 0, "deployer has no balance");

        vm.startBroadcast();
        GasProbe probe = new GasProbe();
        StoragePageProbe pages = new StoragePageProbe();
        vm.stopBroadcast();

        console.log("GasProbe deployed:        ", address(probe));
        console.log("StoragePageProbe deployed:", address(pages));

        // Records are written afterwards by bin/record-deployment.py, from the broadcast
        // artifact. A record written here would carry the *simulation's* block number and no
        // transaction hash at all, because neither exists yet at this point in the script.
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("dry run: nothing broadcast, no deployment record");
        }
    }
}
