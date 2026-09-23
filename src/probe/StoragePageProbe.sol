// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title StoragePageProbe
/// @notice Step 1.5, remainder. Tests the claim that **storage slots are grouped into pages of 128
/// consecutive slots**, where the first touch of a page pays cold and the rest of the page is warm
/// (docs/monad-facts.md §3).
///
/// This one needs a deployed contract. A constructor measures an account mid-creation, which is not
/// the case we care about — the ladder's hot state is read and written by an account that has
/// existed for hours. Once deployed, both measurement functions are reachable by `eth_call`, so
/// only the deployment costs anything.
///
/// The experiment is the layout: slots 0, 1 and 127 are the same page if pages are 128 slots wide,
/// and slot 128 begins a new one. If the claim holds, the gas reads cold-warm-warm-**cold**-warm.
/// This matters more here than the equivalent would on Ethereum: at 8,100 gas a cold page touch is
/// ~4x Ethereum's cold slot, which is what promotes step 4.3 from tidiness to a design constraint.
contract StoragePageProbe {
    constructor() {
        // Populate the slots under test so later reads measure access, not zero-value handling.
        assembly {
            sstore(0, 1)
            sstore(1, 1)
            sstore(127, 1)
            sstore(128, 1)
            sstore(200, 1)
        }
    }

    /// @return g Gas for reads at slots 0, 1, 127, 128, 200 — in that order, in one call.
    function measureSloads() external view returns (uint256[5] memory g) {
        g[0] = _sload(0); // first touch of page 0 — expect cold
        g[1] = _sload(1); // same page — expect warm
        g[2] = _sload(127); // last slot of page 0 — expect warm
        g[3] = _sload(128); // first slot of page 1 — expect cold again
        g[4] = _sload(200); // same page as 128 — expect warm
    }

    /// @return g Gas for writes: new slot in a cold page, new slot in a warm page, existing slot,
    /// and a new slot beyond every slot touched so far.
    /// @dev Not `view`, and called through `eth_call` so nothing persists. The last entry probes
    /// the documented "17,000 per new high-water mark" state-growth charge.
    function measureSstores() external returns (uint256[4] memory g) {
        g[0] = _sstore(300, 7); // new slot, new page, above the high-water mark
        g[1] = _sstore(301, 7); // new slot, page now warm
        g[2] = _sstore(1, 7); // existing slot, page 0 cold on first touch
        g[3] = _sstore(2, 7); // new slot below the high-water mark, page 0 now warm
    }

    function _sload(
        uint256 slot
    ) private view returns (uint256 g) {
        assembly {
            let before := gas()
            let v := sload(slot)
            g := sub(before, gas())
            // Keep the load observable so the optimizer cannot delete the opcode being timed.
            if iszero(v) { g := 0 }
        }
    }

    function _sstore(
        uint256 slot,
        uint256 value
    ) private returns (uint256 g) {
        assembly {
            let before := gas()
            sstore(slot, value)
            g := sub(before, gas())
        }
    }
}
