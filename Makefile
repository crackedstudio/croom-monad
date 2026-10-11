# Commands that touch a key are deliberately separate from commands that do not.
# Everything under "measure" is read-only and needs no account (docs/keys.md).

DEPLOYER_ACCOUNT ?= croom-deployer
# forge script resolves --account only when it broadcasts; the simulation that runs first
# uses Foundry's default sender unless --sender says otherwise. Passing only --account makes
# the script simulate as 0x1804c8...  and fail the deployer assertion before ever prompting
# for a password. Both flags, always.
CHAIN_ID ?= 10143
# /usr/bin/python3 on this machine is Xcode's and refuses to run until the licence is accepted
# (`sudo xcodebuild -license accept`). Point at a working interpreter so the targets below do not
# depend on that being done. Override if yours lives elsewhere.
PYTHON ?= $(shell command -v /opt/homebrew/bin/python3 2>/dev/null || command -v python3)
DEPLOYER_ADDRESS ?= 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8
# The primary public endpoint went down on 11 Oct, two days before the deadline — exactly the
# "deadline-day infrastructure failure" the plan lists as a risk. Override with:
#   make <target> RPC=https://monad-testnet.drpc.org
# Alternatives that answered when the primary did not: monad-testnet.drpc.org, rpc.ankr.com/monad_testnet.
RPC              ?= monad_testnet
export GIT_COMMIT = $(shell git rev-parse --short HEAD)

.PHONY: build test lint check measure-pairing measure-precompiles measure-storage measure-fee-model verify-round sample-verify-gas deploy-entropy prove-round deploy-registry open-rooms deploy-ladder deploy-market web demo-post-lie demo-disprove demo-market-setup demo-market-join demo-market-settle demo-market-claim market-advance-floor market-finalize market-settle fund-challenger whoami-deployer deploy-probe measure-pairing-tx

build:  ; forge build --sizes
test:   ; forge test
lint:   ; forge fmt --check && forge lint
check:  build lint test

# --- read-only measurement: no key, no deployment, no funds ------------------
measure-pairing:
	@cast call --rpc-url $(RPC) --create \
	  $$(forge inspect src/probe/PairingGasReport.sol:PairingGasReport bytecode) \
	  | xargs cast decode-abi "f()(uint256[4],bool[4])"

measure-precompiles:
	@cast call --rpc-url $(RPC) --create \
	  $$(forge inspect src/probe/PrecompileGasReport.sol:PrecompileGasReport bytecode) \
	  | xargs cast decode-abi "f()(uint256[7])"

# Verifies one real drand evmnet round on Monad and reports the cost of each stage.
# Read-only: no key, no deployment, no funds.
verify-round:
	@test -n "$(ROUND)" || (echo "usage: make verify-round ROUND=20880831"; exit 1)
	@SIG=$$(curl -sS "https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/$(ROUND)" \
	  | $(PYTHON) -c 'import sys,json;print(json.load(sys.stdin)["signature"])'); \
	ARGS=$$(cast abi-encode "c(uint64,bytes)" $(ROUND) 0x$$SIG); \
	CODE=$$(forge inspect src/probe/BeaconVerifyReport.sol:BeaconVerifyReport bytecode); \
	echo "verified, gas_hash_to_point, gas_pairing, gas_total:"; \
	cast call --rpc-url $(RPC) --create "$$CODE$${ARGS\#0x}" \
	  | xargs cast decode-abi "f()(bool,uint256,uint256,uint256)"

# Round-by-round spread of verification cost. The maximum is what sets a gas limit.
sample-verify-gas:
	./bin/sample-verify-gas.sh $(or $(COUNT),32) > bench/verify-gas.csv

# Storage paging. Needs the deployed StoragePageProbe address; both calls are read-only.
measure-storage:
	@test -n "$(PROBE)" || (echo "usage: make measure-storage PROBE=0x..."; exit 1)
	@echo "SLOAD  slots 0, 1, 127, 128, 200 (expect cold,warm,warm,COLD,warm):"
	@cast call $(PROBE) "measureSloads()(uint256[5])" --rpc-url $(RPC)
	@echo "SSTORE new/new-warm/existing/new-below-highwater:"
	@cast call $(PROBE) "measureSstores()(uint256[4])" --rpc-url $(RPC)

# --- requires the funded deployer; will prompt for the keystore password -----
deploy-probe:
	forge script script/DeployProbe.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) --broadcast
	$(PYTHON) bin/record-deployment.py broadcast/DeployProbe.s.sol/$(CHAIN_ID)/run-latest.json

# Sends ONE transaction with a padded gas limit to settle whether Monad bills the limit or
# the usage, and re-measures 0x08 through a real transaction at the same time.
measure-fee-model:
	@test -n "$(PROBE)" || (echo "usage: make measure-fee-model PROBE=0x..."; exit 1)
	DEPLOYER_ACCOUNT=$(DEPLOYER_ACCOUNT) DEPLOYER_ADDRESS=$(DEPLOYER_ADDRESS) \
	  ./bin/measure-fee-model.sh $(PROBE)

# Deploys Entropy. Deployment only — see PROVE_GAS below for why proving is separate.
deploy-entropy:
	forge script script/DeployEntropy.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) --broadcast
	$(PYTHON) bin/record-deployment.py broadcast/DeployEntropy.s.sol/$(CHAIN_ID)/run-latest.json

# GATE 1: proves a live drand round against a deployed Entropy, moving the floor on chain.
#
# The gas limit is measured, not estimated. `forge script` and `cast` both size limits from an
# Ethereum gas schedule, and Monad's pairing costs 452,804 more than Ethereum's — so an estimated
# limit is ~2.4x too small, the call runs out of gas, and Monad bills the whole limit anyway.
# 700,000 is ~3% over the measured worst case. See bench/gas-estimation.md.
PROVE_GAS ?= 700000

prove-round:
	@test -n "$(ENTROPY)" || (echo "usage: make prove-round ENTROPY=0x..."; exit 1)
	@ROUND=$$(curl -sS "https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/latest" \
	  | $(PYTHON) -c 'import sys,json;print(json.load(sys.stdin)["round"])'); \
	SIG=$$(curl -sS "https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/$$ROUND" \
	  | $(PYTHON) -c 'import sys,json;print(json.load(sys.stdin)["signature"])'); \
	echo "proving round $$ROUND with a measured limit of $(PROVE_GAS) gas"; \
	cast send $(ENTROPY) "proveRound(uint64,bytes)" $$ROUND 0x$$SIG \
	  --gas-limit $(PROVE_GAS) --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --from $(DEPLOYER_ADDRESS)
	@echo "proven floor is now: $$(cast call $(ENTROPY) 'provenFloor()(uint64)' --rpc-url $(RPC))"

deploy-registry:
	@test -n "$(ENTROPY)" || (echo "usage: make deploy-registry ENTROPY=0x..."; exit 1)
	ENTROPY=$(ENTROPY) forge script script/DeployRegistry.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) --broadcast
	$(PYTHON) bin/record-deployment.py broadcast/DeployRegistry.s.sol/$(CHAIN_ID)/run-latest.json

# GATE 2: opens 50 Rooms across both families and the whole permitted parameter range.
#
# A uniform estimate multiplier is appropriate here, unlike the deploy-then-prove case: all 50
# transactions are the same shape, so one factor covers them all, and padding an ~80k call is
# cheap. The shortfall being corrected is storage and account-access repricing — openRoom reads
# Entropy's floor across a contract boundary (10,100 on Monad against 2,600 on Ethereum) and
# writes a fresh slot (27,900 against 22,100) — not precompiles. See bench/gas-estimation.md.
# Measured: openRoom really costs 77,709 on Monad against forge's 63,086 estimate, a factor of
# 1.23. 1.3 covers it with a little margin. The first run used 1.8 and overpaid by 46%.
ROOMS_GAS_MULTIPLIER ?= 130

open-rooms:
	@test -n "$(REGISTRY)" || (echo "usage: make open-rooms REGISTRY=0x..."; exit 1)
	REGISTRY=$(REGISTRY) forge script script/OpenRooms.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) \
	  --gas-estimate-multiplier $(ROOMS_GAS_MULTIPLIER) --broadcast

deploy-ladder:
	@test -n "$(REGISTRY)" || (echo "usage: make deploy-ladder REGISTRY=0x..."; exit 1)
	REGISTRY=$(REGISTRY) forge script script/DeployLadder.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) --broadcast
	$(PYTHON) bin/record-deployment.py broadcast/DeployLadder.s.sol/$(CHAIN_ID)/run-latest.json

# GATE 3, in two halves run from two different accounts. The liar and the watcher being
# visibly unrelated addresses is part of what the demonstration shows: the watcher holds no
# privilege, no shared secret and no prior arrangement with the poster.
#
# 2.5x because the two shapes differ and the larger is pairing-dominated: post is storage-heavy
# (~1.3x) and disproveTransition verifies a beacon signature (~2.2x). See bench/gas-estimation.md.
DEMO_GAS_MULTIPLIER ?= 250

# The challenger needs gas only — no bond, by design.
CHALLENGER_FUNDING ?= 0.2ether

fund-challenger:
	@test -n "$(TO)" || (echo "usage: make fund-challenger TO=0x..."; exit 1)
	cast send $(TO) --value $(CHALLENGER_FUNDING) --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --from $(DEPLOYER_ADDRESS)

demo-post-lie:
	@test -n "$(LADDER)" || (echo "usage: make demo-post-lie LADDER=0x... ACCOUNT=... FROM=0x..."; exit 1)
	LADDER=$(LADDER) forge script script/DemoPostLie.s.sol --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --sender $(or $(FROM),$(DEPLOYER_ADDRESS)) \
	  --gas-estimate-multiplier $(DEMO_GAS_MULTIPLIER) --broadcast

demo-disprove:
	@test -n "$(LADDER)" || (echo "usage: make demo-disprove LADDER=0x... ACCOUNT=... FROM=0x..."; exit 1)
	LADDER=$(LADDER) forge script script/DemoDisprove.s.sol --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --sender $(or $(FROM),$(DEPLOYER_ADDRESS)) \
	  --gas-estimate-multiplier $(DEMO_GAS_MULTIPLIER) --broadcast

deploy-market:
	@test -n "$(LADDER)" || (echo "usage: make deploy-market LADDER=0x..."; exit 1)
	LADDER=$(LADDER) forge script script/DeployMarket.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) --broadcast
	$(PYTHON) bin/record-deployment.py broadcast/DeployMarket.s.sol/$(CHAIN_ID)/run-latest.json
	$(PYTHON) bin/gen-addresses.py

# Rebuilds the frontend's generated address file and bundle.
web:
	$(PYTHON) bin/gen-addresses.py
	cd web && npm install --silent && npm run build

# ── the live market round, one measured step at a time ───────────────────────────────────────
#
# Not one script with a blanket multiplier. A 2.5x multiplier on forge's Ethereum-priced estimate
# under-funded proveRound by 137,000 gas and killed three transactions in a single broadcast --
# the exact failure bench/gas-estimation.md warns about. Every limit below is measured with
# eth_estimateGas against the deployed contract.
#
# Regenerate the calldata after any contract change:
#   MARKET=0x... forge script script/PrintMarketValues.s.sol --rpc-url $(RPC)

ENTROPY_ADDR ?= 0x09A00a27Cac602e777681F3242f4c7eFe989D4a7
FLOOR_ROUND  ?= 21180000

# Measured 657,015. The limit is the price on Monad, so the margin is small and deliberate.
market-advance-floor:
	@SIG=$$($(PYTHON) -c "import json;print(json.load(open('demo/floor-round.json'))['signatures'][0])"); \
	cast send $(ENTROPY_ADDR) "proveRound(uint64,bytes)" $(FLOOR_ROUND) 0x$$SIG \
	  --gas-limit $(or $(PROVE_GAS),720000) --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --from $(DEPLOYER_ADDRESS)

market-finalize:
	@test -n "$(LADDER)" || (echo "usage: make market-finalize LADDER=0x..."; exit 1)
	cast send $(LADDER) $$(cat demo/finalize.calldata) \
	  --gas-limit $(or $(FINALIZE_GAS),260000) --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --from $(DEPLOYER_ADDRESS)

market-settle:
	@test -n "$(MARKET)" || (echo "usage: make market-settle MARKET=0x..."; exit 1)
	cast send $(MARKET) $$(cat demo/settle.calldata) \
	  --gas-limit $(or $(SETTLE_GAS),420000) --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --from $(or $(FROM),$(DEPLOYER_ADDRESS))

# A complete parimutuel round: honest epoch, finalise, open, stake, settle, claim.
#
# The floor has to land between the challenge window and the market's first round -- proving the
# beacon's latest round instead closes entry on the whole epoch. See DemoMarketSetup.
demo-market-setup:
	@test -n "$(LADDER)" -a -n "$(MARKET)" || (echo "usage: make demo-market-setup LADDER=0x... MARKET=0x..."; exit 1)
	LADDER=$(LADDER) MARKET=$(MARKET) forge script script/DemoMarketSetup.s.sol --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --sender $(or $(FROM),$(DEPLOYER_ADDRESS)) \
	  --gas-estimate-multiplier $(DEMO_GAS_MULTIPLIER) --broadcast

# The other side of the book, from a second account.
demo-market-join:
	@test -n "$(MARKET)" -a -n "$(ID)" -a -n "$(SIDE)" || \
	  (echo "usage: make demo-market-join MARKET=0x... ID=0x... SIDE=0|1 ACCOUNT=... FROM=0x..."; exit 1)
	cast send $(MARKET) "enter(bytes32,uint8)" $(ID) $(SIDE) --value $(or $(STAKE),0.02ether) \
	  --gas-limit $(or $(ENTER_GAS),200000) --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --from $(or $(FROM),$(DEPLOYER_ADDRESS))

# Either side claims; a losing claim reverts, which is correct.
demo-market-claim:
	@test -n "$(MARKET)" -a -n "$(ID)" || (echo "usage: make demo-market-claim MARKET=0x... ID=0x... ACCOUNT=... FROM=0x..."; exit 1)
	cast send $(MARKET) "claim(bytes32)" $(ID) --gas-limit $(or $(CLAIM_GAS),160000) --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --from $(or $(FROM),$(DEPLOYER_ADDRESS))

demo-market-settle:
	@test -n "$(LADDER)" -a -n "$(MARKET)" || (echo "usage: make demo-market-settle LADDER=0x... MARKET=0x..."; exit 1)
	LADDER=$(LADDER) MARKET=$(MARKET) forge script script/DemoMarketSettle.s.sol --rpc-url $(RPC) \
	  --account $(or $(ACCOUNT),$(DEPLOYER_ACCOUNT)) --sender $(or $(FROM),$(DEPLOYER_ADDRESS)) \
	  --gas-estimate-multiplier $(DEMO_GAS_MULTIPLIER) --broadcast

# Confirms the keystore holds the funded address. Prompts for the password and prints an
# address; it signs nothing and sends nothing.
whoami-deployer:
	@cast wallet address --account $(DEPLOYER_ACCOUNT)

# End-to-end cost of one pairing check as a real transaction, for comparison
# against the eth_call figure in bench/precompiles.md.
measure-pairing-tx:
	@test -n "$(PROBE)" || (echo "usage: make measure-pairing-tx PROBE=0x..."; exit 1)
	cast send $(PROBE) "checkPairing(bytes)" \
	  $$(cast abi-encode "f(uint256[12])" "[1,2,11559732032986387107991004021392285783925812861821192530917403151452391805634,10857046999023057135944570762232829481370756359578518086990519993285655852781,4082367875863433681332203403145435568316851327593401208105741076214120093531,8495653923123431417604973247489272438418190587263600148770280649306958101930,1,21888242871839275222246405745257275088696311157297823662689037894645226208581,11559732032986387107991004021392285783925812861821192530917403151452391805634,10857046999023057135944570762232829481370756359578518086990519993285655852781,4082367875863433681332203403145435568316851327593401208105741076214120093531,8495653923123431417604973247489272438418190587263600148770280649306958101930]") \
	  --rpc-url $(RPC) --account $(DEPLOYER_ACCOUNT)
