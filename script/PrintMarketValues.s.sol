// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ladder} from "../src/Ladder.sol";
import {Market} from "../src/Market.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {DemoBase} from "./DemoBase.s.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {console} from "forge-std/Script.sol";

/// @notice Prints the values and calldata the remaining market steps need, so each can be sent
/// with `cast` under a **measured** gas limit rather than a multiplied estimate.
///
/// Written after a blanket 2.5x multiplier under-funded a pairing call by 137,000 gas and killed
/// three transactions in one broadcast. `bench/gas-estimation.md` already said no single
/// multiplier is safe; this is the tooling that makes following that advice convenient.
contract PrintMarketValues is DemoBase {
    uint64 internal constant MARKET_START = GENESIS + 2;
    uint64 internal constant MARKET_END = GENESIS + 15;

    function run() external {
        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);
        (bytes32[] memory leaves, int256[] memory closes, int256[] memory highs, int256[] memory lows) =
            _deriveHonest(spec);

        int128 endPrice = int128(closes[EPOCH_ROUNDS - 1]);
        console.log("epoch end price (int128):");
        console.logInt(endPrice);

        console.log("");
        console.log("finalize calldata:");
        console.logBytes(abi.encodeCall(Ladder.finalize, (spec, 0, endPrice)));

        Market market = Market(vm.envAddress("MARKET"));
        bytes32 id = market.marketId(RoomSpec.roomId(spec), MARKET_START, MARKET_END);
        console.log("");
        console.log("market id:");
        console.logBytes32(id);

        console.log("");
        console.log("settle calldata:");
        console.logBytes(
            abi.encodeCall(
                Market.settle,
                (
                    spec,
                    id,
                    0,
                    _claim(leaves, closes, highs, lows, MARKET_START - GENESIS),
                    0,
                    _claim(leaves, closes, highs, lows, MARKET_END - GENESIS)
                )
            )
        );
    }
}
