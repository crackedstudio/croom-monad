// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath as F} from "./FixedPointMath.sol";

/// @title RoomSpec
/// @notice A Room's immutable definition, its canonical encoding, and its identity. Ported from
/// `croom-core`'s `spec.rs`; the layout is `docs/core-v1.md` §3 and §4.
///
/// `roomId = keccak256(encode(spec))`. The registry stores the hash and emits the body, so
/// immutability is **structural**: there is no field an administrator could change, because
/// changing any field produces a different Room.
///
/// Every integer is big-endian and fixed-width, with no length prefixes and no padding, so the
/// encoding is unambiguous and two specs collide only if they are byte-identical.
///
/// **`i128` fields encode as 16 bytes, not 32.** The reference's native width is `i128`, and a
/// 32-byte encoding would produce a different `roomId` for the same Room — the kind of divergence
/// that looks like nothing until no Room on this chain matches its counterpart anywhere else.
library RoomSpec {
    uint8 internal constant ENCODING_VERSION = 1;
    uint8 internal constant MATH_VERSION = 1;
    uint8 internal constant HASH_FN = 1;
    /// @dev drand evmnet. `R_r` differs per beacon network, so the beacon is part of a Room's
    /// identity rather than a deployment setting.
    uint8 internal constant BEACON_EVMNET = 0;

    uint8 internal constant FAMILY_DRIFT = 0;
    uint8 internal constant FAMILY_STEP = 1;

    error UnsupportedFamily(uint8 family);
    error ValueOutOfI128Range(int256 value);

    /// @param param Drift: `sigma`, annualised volatility in WAD. Step: `step`, the fixed move.
    struct Spec {
        uint8 family;
        uint8 beacon;
        uint8 subTicks;
        uint32 epochRounds;
        uint64 genesisRound;
        int256 initialPrice;
        uint8 decimals;
        uint8 mathVersion;
        uint8 hashFn;
        int256 param;
    }

    /// @param level Index into a family's regime table. Unused by Drift and Step, carried so the
    /// state encoding matches the reference byte for byte.
    /// @param lo Range family's lower border. Unused here, same reason.
    /// @param hi Range family's upper border.
    struct State {
        int256 price;
        uint8 level;
        int256 lo;
        int256 hi;
    }

    /// @notice The canonical encoding — 51 bytes for both families we ship.
    function encode(
        Spec memory s
    ) internal pure returns (bytes memory) {
        if (s.family != FAMILY_DRIFT && s.family != FAMILY_STEP) revert UnsupportedFamily(s.family);

        return abi.encodePacked(
            ENCODING_VERSION,
            s.family,
            s.beacon,
            s.subTicks,
            s.epochRounds,
            s.genesisRound,
            _i128(s.initialPrice),
            s.decimals,
            s.mathVersion,
            s.hashFn,
            _i128(s.param)
        );
    }

    function roomId(
        Spec memory s
    ) internal pure returns (bytes32) {
        return keccak256(encode(s));
    }

    /// @notice 50 bytes: `family ‖ price ‖ level ‖ lo ‖ hi`.
    /// @dev The family is bound into the state as well as the spec, so a state cannot be replayed
    /// against a Room of a different family even if the prices happen to coincide.
    function encodeState(
        uint8 family,
        State memory st
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(family, _i128(st.price), st.level, _i128(st.lo), _i128(st.hi));
    }

    function stateHash(
        uint8 family,
        State memory st
    ) internal pure returns (bytes32) {
        return keccak256(encodeState(family, st));
    }

    /// @notice The first round of epoch `e`.
    function epochStart(
        Spec memory s,
        uint64 epoch
    ) internal pure returns (uint64) {
        return s.genesisRound + epoch * s.epochRounds;
    }

    /// @notice Big-endian two's complement in 16 bytes, the reference's `i128` width.
    /// @dev Range-checked rather than truncated. Silently narrowing here would produce a valid
    /// encoding of the wrong Room.
    function _i128(
        int256 v
    ) private pure returns (bytes16) {
        if (v < F.INT128_MIN || v > F.INT128_MAX) revert ValueOutOfI128Range(v);
        // casting is safe because the i128 range was just checked; int128 -> uint128 is a
        // two's complement reinterpretation, which is exactly the encoding required.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes16(uint128(int128(v)));
    }
}
