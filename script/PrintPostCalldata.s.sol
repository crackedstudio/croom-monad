// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;
import {DemoBase} from "../script/DemoBase.s.sol";
import {OpenRooms} from "../script/OpenRooms.s.sol";
import {Ladder} from "../src/Ladder.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {console} from "forge-std/Script.sol";

/// @notice Prints the exact calldata for a `post`, so it can be priced with `eth_estimateGas`
/// against the live contract — the only method that applies Monad's own gas schedule.
///
/// ```bash
/// DATA=$(forge script script/PrintPostCalldata.s.sol | grep -oE "0x[0-9a-f]{200,}")
/// cast estimate <ladder> "$DATA" --value 0.05ether --rpc-url monad_testnet --from <poster>
/// ```
///
/// Exists because a struct-array argument is awkward to encode on the `cast` command line, and
/// guessing a gas figure for a submission is worse than writing twenty lines to measure it.
contract PrintPostCalldata is DemoBase {
    function run() external {
        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);
        (, int256[] memory closes, int256[] memory highs, int256[] memory lows) = _deriveEpoch(spec);

        Ladder.PostedLeaf[] memory published = new Ladder.PostedLeaf[](EPOCH_ROUNDS);
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            published[i] = Ladder.PostedLeaf({
                round: GENESIS + uint64(i),
                close: int128(closes[i]),
                high: int128(highs[i]),
                low: int128(lows[i])
            });
        }
        bytes32 prior = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(spec.initialPrice), level: 0, lo: 0, hi: 0})
        );
        bytes32 end = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(closes[EPOCH_ROUNDS - 1]), level: 0, lo: 0, hi: 0})
        );
        console.logBytes(abi.encodeCall(Ladder.post, (spec, 0, prior, end, published)));
    }
}
