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
RPC              ?= monad_testnet
export GIT_COMMIT = $(shell git rev-parse --short HEAD)

.PHONY: build test lint check measure-pairing measure-precompiles measure-storage measure-fee-model verify-round sample-verify-gas deploy-entropy prove-round deploy-registry open-rooms whoami-deployer deploy-probe measure-pairing-tx

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
ROOMS_GAS_MULTIPLIER ?= 180

open-rooms:
	@test -n "$(REGISTRY)" || (echo "usage: make open-rooms REGISTRY=0x..."; exit 1)
	REGISTRY=$(REGISTRY) forge script script/OpenRooms.s.sol --rpc-url $(RPC) \
	  --account $(DEPLOYER_ACCOUNT) --sender $(DEPLOYER_ADDRESS) \
	  --gas-estimate-multiplier $(ROOMS_GAS_MULTIPLIER) --broadcast

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
