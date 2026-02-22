#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

: "${PRIVATE_KEY:?PRIVATE_KEY is required}"

RPC_URL="${MEGAETH_RPC_URL:-https://mainnet.megaeth.com/rpc}"
GAS_PRICE_WEI="${MEGAETH_GAS_PRICE_WEI:-1000000}"
GAS_BUFFER_BPS="${MEGAETH_GAS_BUFFER_BPS:-12000}"

PRISM_FACTORY="0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef"
KUMBAYA_FACTORY="0x68b34591f662508076927803c567Cc8006988a09"
WETH="0x4200000000000000000000000000000000000006"
USDM="0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7"
USDT0="0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb"
BTCB="0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072"

PRISM_WETH_USDM_POOL="0xC2FaC0B5B6C075819E654bcFbBBCda2838609d32"
KUMBAYA_WETH_USDM_POOL="0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22"
KUMBAYA_WETH_USDT0_POOL="0x2809696F2e42eB452C32C3d0A2Dc540858C14125"
KUMBAYA_BTCB_USDM_POOL="0xc1838B7807e5bd4D56EA630BA35Ac964CF72c9db"
KUMBAYA_USDT0_USDM_POOL="0x6c8E5D463a2473b1A8bcd87e1cEA2724203A1D8f"

CANONIC_MAOB_WETH_USDM="0x23469683e25b780DFDC11410a8e83c923caDF125"
CANONIC_MAOB_BTCB_USDM="0xaD7e5CBfB535ceC8d2E58Dca17b11d9bA76f555E"
CANONIC_MAOB_USDT0_USDM="0xDf1576c3C82C9f8B759C69f4cF256061C6Fe1f9e"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd "$HOME/.foundry/bin/cast"
require_cmd jq
require_cmd sed
require_cmd tr

CAST="$HOME/.foundry/bin/cast"
DEPLOYER="$($CAST wallet address --private-key "$PRIVATE_KEY")"

to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

with_buffer() {
  local gas_estimate="$1"
  echo $((gas_estimate * GAS_BUFFER_BPS / 10000))
}

extract_tx_hash() {
  local tx_json="$1"
  local tx_hash
  tx_hash="$(echo "$tx_json" | jq -r '.transactionHash // .hash // empty')"
  if [[ -z "$tx_hash" ]]; then
    tx_hash="$(echo "$tx_json" | grep -Eo '0x[a-fA-F0-9]{64}' | head -n 1)"
  fi
  if [[ -z "$tx_hash" ]]; then
    echo "failed to parse transaction hash" >&2
    echo "$tx_json" >&2
    exit 1
  fi
  echo "$tx_hash"
}

assert_receipt_success() {
  local receipt_json="$1"
  local status
  status="$(echo "$receipt_json" | jq -r '.status')"
  if [[ "$status" != "1" && "$status" != "0x1" ]]; then
    echo "transaction failed, receipt:" >&2
    echo "$receipt_json" >&2
    exit 1
  fi
}

estimate_create() {
  local bytecode="$1"
  "$CAST" estimate \
    --rpc-url "$RPC_URL" \
    --from "$DEPLOYER" \
    --legacy \
    --gas-price "$GAS_PRICE_WEI" \
    --create "$bytecode"
}

send_create() {
  local label="$1"
  local bytecode="$2"
  local estimated_gas gas_limit tx_json tx_hash receipt_json contract_address

  estimated_gas="$(estimate_create "$bytecode")"
  gas_limit="$(with_buffer "$estimated_gas")"

  echo "deploying $label (estimate=$estimated_gas, gas_limit=$gas_limit)" >&2
  tx_json="$(
    "$CAST" send \
      --json \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --legacy \
      --gas-price "$GAS_PRICE_WEI" \
      --gas-limit "$gas_limit" \
      --create "$bytecode"
  )"
  tx_hash="$(extract_tx_hash "$tx_json")"
  receipt_json="$("$CAST" receipt --json "$tx_hash" --rpc-url "$RPC_URL")"
  assert_receipt_success "$receipt_json"

  contract_address="$(echo "$receipt_json" | jq -r '.contractAddress')"
  if [[ -z "$contract_address" || "$contract_address" == "null" ]]; then
    echo "missing contractAddress in receipt for $label" >&2
    echo "$receipt_json" >&2
    exit 1
  fi

  echo "  tx: $tx_hash" >&2
  echo "  address: $contract_address" >&2
  echo "$contract_address"
}

estimate_call() {
  local to="$1"
  local sig="$2"
  shift 2
  "$CAST" estimate \
    --rpc-url "$RPC_URL" \
    --from "$DEPLOYER" \
    --legacy \
    --gas-price "$GAS_PRICE_WEI" \
    "$to" "$sig" "$@"
}

send_call() {
  local label="$1"
  local to="$2"
  local sig="$3"
  shift 3
  local estimated_gas gas_limit tx_json tx_hash receipt_json

  estimated_gas="$(estimate_call "$to" "$sig" "$@")"
  gas_limit="$(with_buffer "$estimated_gas")"

  echo "calling $label (estimate=$estimated_gas, gas_limit=$gas_limit)"
  tx_json="$(
    "$CAST" send \
      --json \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --legacy \
      --gas-price "$GAS_PRICE_WEI" \
      --gas-limit "$gas_limit" \
      "$to" "$sig" "$@"
  )"
  tx_hash="$(extract_tx_hash "$tx_json")"
  receipt_json="$("$CAST" receipt --json "$tx_hash" --rpc-url "$RPC_URL")"
  assert_receipt_success "$receipt_json"
  echo "  tx: $tx_hash"
}

artifact_bytecode() {
  local artifact="$1"
  jq -r '.bytecode.object' "$artifact"
}

append_constructor_address() {
  local bytecode="$1"
  local addr="$2"
  local encoded
  encoded="$("$CAST" abi-encode "constructor(address)" "$addr")"
  echo "${bytecode}${encoded#0x}"
}

mkdir -p deployments

echo "deployer: $DEPLOYER"
echo "rpc: $RPC_URL"
echo "gas_price_wei: $GAS_PRICE_WEI"
echo "gas_buffer_bps: $GAS_BUFFER_BPS"

PRISM_QUOTER_BYTECODE="$(append_constructor_address "$(artifact_bytecode "out/MegaethViewQuoter.sol/MegaethViewQuoter.json")" "$PRISM_FACTORY")"
KUMBAYA_QUOTER_BYTECODE="$(append_constructor_address "$(artifact_bytecode "out/MegaethViewQuoter.sol/MegaethViewQuoter.json")" "$KUMBAYA_FACTORY")"
CONTRAPARTY_BYTECODE="$(artifact_bytecode "out/ContrapartyV2.vy/ContrapartyV2.json")"

prism_quoter="$(send_create "MegaethViewQuoter(prism)" "$PRISM_QUOTER_BYTECODE")"
kumbaya_quoter="$(send_create "MegaethViewQuoter(kumbaya)" "$KUMBAYA_QUOTER_BYTECODE")"
contraparty="$(send_create "ContrapartyV2" "$CONTRAPARTY_BYTECODE")"

PRISM_AMM_BYTECODE="$(append_constructor_address "$(artifact_bytecode "out/UniswapV3PropAMM.vy/UniswapV3PropAMM.json")" "$prism_quoter")"
KUMBAYA_AMM_BYTECODE="$(append_constructor_address "$(artifact_bytecode "out/UniswapV3PropAMM.vy/UniswapV3PropAMM.json")" "$kumbaya_quoter")"
CANONIC_AMM_BYTECODE="$(artifact_bytecode "out/CanonicPropAMM.vy/CanonicPropAMM.json")"

prism_amm="$(send_create "UniswapV3PropAMM(prism)" "$PRISM_AMM_BYTECODE")"
kumbaya_amm="$(send_create "UniswapV3PropAMM(kumbaya)" "$KUMBAYA_AMM_BYTECODE")"
canonic_amm="$(send_create "CanonicPropAMM" "$CANONIC_AMM_BYTECODE")"

send_call "register_pool prism WETH/USDM" "$prism_amm" "register_pool(address,uint24)" "$PRISM_WETH_USDM_POOL" 3000

send_call "register_pool kumbaya WETH/USDM" "$kumbaya_amm" "register_pool(address,uint24)" "$KUMBAYA_WETH_USDM_POOL" 3000
send_call "register_pool kumbaya WETH/USDT0" "$kumbaya_amm" "register_pool(address,uint24)" "$KUMBAYA_WETH_USDT0_POOL" 3000
send_call "register_pool kumbaya BTCB/USDM" "$kumbaya_amm" "register_pool(address,uint24)" "$KUMBAYA_BTCB_USDM_POOL" 3000
send_call "register_pool kumbaya USDT0/USDM" "$kumbaya_amm" "register_pool(address,uint24)" "$KUMBAYA_USDT0_USDM_POOL" 100

send_call "register_market canonic WETH/USDM" "$canonic_amm" "register_market(address)" "$CANONIC_MAOB_WETH_USDM"
send_call "register_market canonic BTCB/USDM" "$canonic_amm" "register_market(address)" "$CANONIC_MAOB_BTCB_USDM"
send_call "register_market canonic USDT0/USDM" "$canonic_amm" "register_market(address)" "$CANONIC_MAOB_USDT0_USDM"

send_call "register_amm prism" "$contraparty" "register_amm(address)" "$prism_amm"
send_call "register_amm kumbaya" "$contraparty" "register_amm(address)" "$kumbaya_amm"
send_call "register_amm canonic" "$contraparty" "register_amm(address)" "$canonic_amm"

timestamp="$(date +%s)"
cat > deployments/megaeth.toml <<EOF
[megaeth]
chain = "megaeth"
chain_id = 4326
contraparty_version = "v2"
contraparty = "$(to_lower "$contraparty")"
deployed_at_unix = $timestamp

[megaeth.factories]
prism = "$(to_lower "$PRISM_FACTORY")"
kumbaya = "$(to_lower "$KUMBAYA_FACTORY")"

[megaeth.quoters]
prism = "$(to_lower "$prism_quoter")"
kumbaya = "$(to_lower "$kumbaya_quoter")"

[megaeth.amms]
prism_uniswap_v3 = "$(to_lower "$prism_amm")"
kumbaya_uniswap_v3 = "$(to_lower "$kumbaya_amm")"
canonic = "$(to_lower "$canonic_amm")"

[megaeth.canonic_maobs]
weth_usdm = "$(to_lower "$CANONIC_MAOB_WETH_USDM")"
btcb_usdm = "$(to_lower "$CANONIC_MAOB_BTCB_USDM")"
usdt0_usdm = "$(to_lower "$CANONIC_MAOB_USDT0_USDM")"

[megaeth.pools.prism_weth_usdm]
address = "$(to_lower "$PRISM_WETH_USDM_POOL")"
fee = 3000
token0 = "$(to_lower "$WETH")"
token1 = "$(to_lower "$USDM")"

[megaeth.pools.kumbaya_weth_usdm]
address = "$(to_lower "$KUMBAYA_WETH_USDM_POOL")"
fee = 3000
token0 = "$(to_lower "$WETH")"
token1 = "$(to_lower "$USDM")"

[megaeth.pools.kumbaya_weth_usdt0]
address = "$(to_lower "$KUMBAYA_WETH_USDT0_POOL")"
fee = 3000
token0 = "$(to_lower "$WETH")"
token1 = "$(to_lower "$USDT0")"

[megaeth.pools.kumbaya_btcb_usdm]
address = "$(to_lower "$KUMBAYA_BTCB_USDM_POOL")"
fee = 3000
token0 = "$(to_lower "$BTCB")"
token1 = "$(to_lower "$USDM")"

[megaeth.pools.kumbaya_usdt0_usdm]
address = "$(to_lower "$KUMBAYA_USDT0_USDM_POOL")"
fee = 100
token0 = "$(to_lower "$USDT0")"
token1 = "$(to_lower "$USDM")"
EOF

echo ""
echo "deployment complete"
echo "contraparty:  $contraparty"
echo "prism quoter: $prism_quoter"
echo "kumbaya quoter: $kumbaya_quoter"
echo "prism amm:    $prism_amm"
echo "kumbaya amm:  $kumbaya_amm"
echo "canonic amm:  $canonic_amm"
echo "deployment file: deployments/megaeth.toml"
