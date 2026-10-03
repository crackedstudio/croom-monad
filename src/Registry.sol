// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "./Entropy.sol";
import {RoomSpec} from "./RoomSpec.sol";
import {Tick} from "./Tick.sol";

/// @title Registry
/// @notice Permissionless Room creation. A Room is opened by submitting an immutable spec;
/// `roomId` is the hash of that spec's canonical encoding.
///
/// **Immutability is structural, not promised.** The contract stores the hash and emits the body,
/// so there is no field an administrator could change — changing any field yields a different
/// Room. There is no owner, no pause, no upgrade path, and no function that writes to an existing
/// Room's record once set.
///
/// The creator is recorded because the protocol pays them a share of rake (spec v1.1 §7.3). It is
/// a revenue claim on a market they cannot touch: a creator cannot pause a Room, change its
/// parameters, or influence a single tick.
contract Registry {
    /// @notice The beacon floor this registry reads to enforce the fairness rule below.
    Entropy public immutable entropy;

    /// @notice `B` — how far above the proven floor a Room's first round must sit.
    /// @dev Spec v1.1 Appendix C: 2 rounds. Measured in **rounds above the proven floor**, never
    /// in seconds: a chain timestamp is an estimate of when a round existed, and on Monad it
    /// cannot even distinguish adjacent blocks.
    uint64 public constant ENTRY_BUFFER = 2;

    // Governance bounds, spec v1.1 §7.2, at their hard limits. Compiled in: this deployment has
    // no governance, so the hard limits are the only limits.
    int256 internal constant SIGMA_MIN = 1e16; // 1% a year
    int256 internal constant SIGMA_MAX = 10e18; // 1000% a year
    uint32 internal constant EPOCH_MIN = 20;
    uint32 internal constant EPOCH_MAX = 1200;
    uint8 internal constant SUB_TICKS_MAX = 3;

    /// @notice Who opened a Room. The zero address means the Room does not exist.
    /// @dev The only mutable storage, and it is write-once per key — enforced by `AlreadyOpen`.
    mapping(bytes32 => address) public creatorOf;

    /// @notice The full spec body, for indexers and for anyone recomputing history.
    /// @dev Emitted rather than stored. The chain keeps 32 bytes; the 51-byte body lives in the
    /// log, where it costs a fraction as much and is just as permanent.
    event RoomOpened(bytes32 indexed roomId, address indexed creator, bytes spec);

    error AlreadyOpen(bytes32 roomId);
    error UnsupportedFamily(uint8 family);
    error BadVersion();
    error BadBeacon();
    error GenesisNotInFuture(uint64 genesisRound, uint64 provenFloor);
    error SubTicksOutOfRange(uint8 subTicks);
    error EpochRoundsOutOfRange(uint32 epochRounds);
    error InitialPriceOutOfRange(int256 price);
    error SigmaOutOfRange(int256 sigma);
    error StepOutOfRange(int256 step);

    constructor(
        Entropy entropy_
    ) {
        entropy = entropy_;
    }

    /// @notice Opens a Room. Anyone may call this, for any valid spec, at any time.
    function openRoom(
        RoomSpec.Spec calldata spec
    ) external returns (bytes32 roomId) {
        _validate(spec);

        bytes memory encoded = RoomSpec.encode(spec);
        roomId = keccak256(encoded);

        if (creatorOf[roomId] != address(0)) revert AlreadyOpen(roomId);
        creatorOf[roomId] = msg.sender;

        emit RoomOpened(roomId, msg.sender, encoded);
    }

    function isOpen(
        bytes32 roomId
    ) external view returns (bool) {
        return creatorOf[roomId] != address(0);
    }

    /// @dev Structural rules first, then the governance bounds, then the fairness rule.
    function _validate(
        RoomSpec.Spec calldata spec
    ) internal view {
        if (spec.family != RoomSpec.FAMILY_DRIFT && spec.family != RoomSpec.FAMILY_STEP) {
            revert UnsupportedFamily(spec.family);
        }
        if (spec.mathVersion != RoomSpec.MATH_VERSION || spec.hashFn != RoomSpec.HASH_FN) {
            revert BadVersion();
        }
        if (spec.beacon != RoomSpec.BEACON_EVMNET) revert BadBeacon();

        if (spec.subTicks == 0 || spec.subTicks > SUB_TICKS_MAX) revert SubTicksOutOfRange(spec.subTicks);
        if (spec.epochRounds < EPOCH_MIN || spec.epochRounds > EPOCH_MAX) {
            revert EpochRoundsOutOfRange(spec.epochRounds);
        }
        if (spec.initialPrice <= 0 || spec.initialPrice > Tick.PRICE_MAX) {
            revert InitialPriceOutOfRange(spec.initialPrice);
        }

        if (spec.family == RoomSpec.FAMILY_DRIFT) {
            if (spec.param < SIGMA_MIN || spec.param > SIGMA_MAX) revert SigmaOutOfRange(spec.param);
        } else {
            // A step larger than the price could cross zero in one tick; the model floors at the
            // step size, so this keeps the floor below the opening price rather than above it.
            if (spec.param <= 0 || spec.param > spec.initialPrice) revert StepOutOfRange(spec.param);
        }

        // **The fairness rule (spec v1.1, P2).** A Room's first round must not exist yet. Without
        // this, someone could open a Room whose history is already determined, read the beacon
        // they already have, and pick parameters that make the opening chart flatter.
        //
        // Keyed to the proven floor, so it is a statement about what has been *proven* to exist
        // rather than a guess at the time. A stale floor only pushes genesis further out, which is
        // safe; nothing can lower the floor.
        uint64 floor = entropy.provenFloor();
        if (spec.genesisRound <= floor + ENTRY_BUFFER) {
            revert GenesisNotInFuture(spec.genesisRound, floor);
        }
    }
}
