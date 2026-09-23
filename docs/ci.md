# CI

`.github/workflows/ci.yml` runs on every push and pull request under the `ci` profile
(8,192 fuzz runs, 1,024 invariant runs — see `foundry.toml`).

It does four things, and the last two are the ones that matter:

1. **Pins the toolchain and asserts the pin held.** A CI run on a different compiler proves nothing about the artifact we submit.
2. **`forge fmt --check`** — formatting arguments are not a good use of the 20 days.
3. **`forge build --sizes`** — Monad caps contracts at 128 KB and init code at 256 KB. An overrun should fail on the commit that causes it, not on deploy day.
4. **Asserts that tests actually ran.** A suite that silently matched zero tests reports green. That failure mode is quiet, and it is exactly the kind of thing that lets a broken conformance claim survive to submission.

The nightly full-vector sweep and long fuzz (`deep` profile) land in step 7.3, once there is a
complete vector set to sweep.

## What CI does not do

No testnet deploys, no key material, no faucet calls. Deployment is a deliberate local act that
writes a file into `deployments/`; a workflow that can spend the deployer's balance is a workflow
that can be triggered by a pull request.
