# Toolchain

Everything here is pinned. The submission's central claim is that a third party can recompute a
Room's history and get bit-identical results; that claim is not reproducible on a floating
toolchain.

| Tool | Pin | Where |
| --- | --- | --- |
| Foundry | `1.4.3-stable` (`fa9f934`) | `.tool-versions` |
| solc | `0.8.28` | `foundry.toml` → `solc_version` |
| forge-std | `v1.9.7` (`77041d2`) | `lib/` submodule gitlink |
| Node | `20.13.1` | `.tool-versions` |

## Settings that are decisions, not defaults

**`evm_version = "cancun"`** — Monad supports every opcode as of the **Fusaka** fork
(`docs/monad-facts.md` §2), so transient storage and `MCOPY` are available. solc `0.8.28` cannot
express anything later than `cancun`, so this is the ceiling of the pinned compiler rather than a
ceiling of the chain. Raising it further means moving the solc pin first, and re-running the
conformance sweep after.

**`bytecode_hash = "none"`, `cbor_metadata = false`** — identical sources produce identical
bytecode, so anyone can reproduce our deployed artifacts without matching our metadata.

**`optimizer_runs = 1_000_000`** — the derivation library and the fraud-proof terminal step are
called far more often than they are deployed, and Monad charges the sender on `gas_limit`. Deploy
cost is a one-off; the terminal step's cost decides whether an honest challenger is economically
viable.

**`fuzz.runs = 1024` by default, `8192` in CI, `262_144` in `deep`** — rounding is the whole game
(PLAN.md §6). A truncation bug that appears once in ten thousand runs is a bug we ship.

**`deny = "warnings"`** — a shadowed name or an unused parameter is exactly how a derivation
silently reads the wrong variable.

**`invariant.fail_on_revert = false`** — the ladder's adversarial suite drives reverting paths on
purpose; the invariant under test is *a dishonest poster loses*, not *no call ever reverts*.

## Setup on a fresh machine

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup --install v1.4.3
git clone <repo> && cd croom-evm
git submodule update --init --recursive
cp .env.example .env   # then fill it in
forge build && forge test
```
