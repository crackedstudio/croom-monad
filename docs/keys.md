# Key policy

**No private key is ever written to a file in this repository, including `.env`.** Foundry's
encrypted keystore holds the material; the repo only ever names an account.

```bash
cast wallet import croom-deployer --interactive
```

Scripts and bots then reference the account by name:

```bash
forge script script/Deploy.s.sol --rpc-url monad_testnet --account croom-deployer --broadcast
```

## Four accounts, deliberately separate

| Account | Role | Why it is its own key |
| --- | --- | --- |
| `croom-deployer` | deploys contracts | The only account whose address ends up in a submission README |
| `croom-poster` | posts checkpoints (step 5.4) | Runs unattended for hours; a compromised bot key should not be able to touch deployments |
| `croom-challenger` | honest challenger | Must be a stranger to the poster for the fraud proof to demonstrate anything |
| `croom-liar` | posts the knowingly dishonest checkpoint in the demo | **Designed to lose its bond.** Fund it from the faucet with exactly the bond and nothing more |

The liar and the challenger being visibly unrelated addresses is part of what the demo proves: the
honest challenger has no special privilege. Reusing one key for both makes the strongest beat of
the submission look staged.

## Rules

- Testnet funds only. No account here ever holds mainnet MON.
- Nothing in CI can sign. Deployment is a local, deliberate act that writes into `deployments/`.
- If a key is ever pasted into a terminal that gets committed, screenshotted, or shared in the demo video, rotate it and redeploy — cheap now, expensive on day 19.
- The demo video is a recording of a screen. Check the frame for keystore prompts and funded balances before publishing.
