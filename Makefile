# Commands that touch a key are deliberately separate from commands that do not.
# Everything under "measure" is read-only and needs no account (docs/keys.md).

DEPLOYER_ACCOUNT ?= croom-deployer
# forge script resolves --account only when it broadcasts; the simulation that runs first
# uses Foundry's default sender unless --sender says otherwise. Passing only --account makes
# the script simulate as 0x1804c8...  and fail the deployer assertion before ever prompting
# for a password. Both flags, always.
CHAIN_ID ?= 10143
DEPLOYER_ADDRESS ?= 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8
RPC              ?= monad_testnet
export GIT_COMMIT = $(shell git rev-parse --short HEAD)

.PHONY: build test lint check measure-pairing measure-precompiles measure-storage measure-fee-model whoami-deployer deploy-probe measure-pairing-tx

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
	./bin/record-deployment.py broadcast/DeployProbe.s.sol/$(CHAIN_ID)/run-latest.json

# Sends ONE transaction with a padded gas limit to settle whether Monad bills the limit or
# the usage, and re-measures 0x08 through a real transaction at the same time.
measure-fee-model:
	@test -n "$(PROBE)" || (echo "usage: make measure-fee-model PROBE=0x..."; exit 1)
	DEPLOYER_ACCOUNT=$(DEPLOYER_ACCOUNT) DEPLOYER_ADDRESS=$(DEPLOYER_ADDRESS) \
	  ./bin/measure-fee-model.sh $(PROBE)

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
