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

## A local hazard worth knowing about

`forge build` runs the linter, and `deny = "warnings"` makes a lint finding abort the build. If that
happens, **artifacts for the file you just added are never written** — and a subsequent `forge test`
quietly falls back to the cached artifacts and reports green on the *old* set of tests. Observed on
23 Sep: a lint abort caused a run to report `8 passed` when the suite actually held 13, with an
entire test file silently absent.

CI is not exposed to this — it checks out fresh and its `build` step fails the job outright. The
trap is local, and it is a nasty one because the signal is a green suite.

Two habits that defuse it:

- Run `make check` rather than `forge test` alone. It is ordered `build lint test`, so a lint abort stops the chain instead of falling through to a stale pass.
- Treat a *drop* in the reported test count as a failure, not a curiosity. `forge test --list` shows what the binary actually contains; `forge clean` resolves any doubt.

## The same trap, a fourth time

`forge clean` was needed again on 11 October, and the symptom was different enough to waste time:
`forge script` failed with **"Could not find target contract"** while `forge build` reported
"No files changed, compilation skipped" and the artifact JSON was sitting right there — with
`bytecode` present but empty.

Foundry's cache and `out/` can disagree, and when they do the error names the wrong thing. The
`deny = "warnings"` abort was one way to get there; an interrupted build is another, and on this
occasion the interruption was a network timeout killing `forge script` mid-compile.

`bin/redeploy.sh` now begins with `forge clean`. Ten seconds of rebuilding beats diagnosing this
again with two days left.
