## Contraparty Foundry (Base)

This directory contains:
- Vyper `Contraparty` contract.
- Vyper Prop AMMs for Base:
  - `UniswapV3PropAMM.vy`
  - `UniswapV2PropAMM.vy`
  - `AerodromePropAMM.vy`
- Forge scripts for deployment and swap execution on Base mainnet.

## 1. Configure Environment

Create a local env file:

```bash
cp .env.example .env
```

Fill at least:

```bash
BASE_RPC_URL=https://base.llamarpc.com
PRIVATE_KEY=0x<YOUR_PRIVATE_KEY>
SWAP_AMOUNT_IN_WEI=10000000000000000
SWAP_SLIPPAGE_BPS=50
```

## 2. Where To Store Mainnet Key

Store your key in:
- `.env` as `PRIVATE_KEY=0x...`

Do not commit `.env`.
- `.env` is already ignored by git in this repository.

Recommended:
- Use a dedicated deployer key with limited funds.
- Prefer hardware-wallet controlled operational flow for production.

## 3. Build

```bash
forge build
```

## 4. Deploy Contraparty + Vyper AMMs On Base

```bash
source .env
forge script script/DeployBaseVyperStack.s.sol:DeployBaseVyperStack \
  --rpc-url base \
  --broadcast \
  --private-key $PRIVATE_KEY
```

This script deploys and registers:
- `Contraparty.vy`
- `UniswapV3PropAMM.vy`
- `UniswapV2PropAMM.vy`
- `AerodromePropAMM.vy`

Deployment info is saved automatically to:
- `deployments/base.toml`

Template file:
- `deployments/base.example.toml`

## 5. Run Real Swap (WETH -> USDC) On Base

The swap script reads Contraparty address from:
- `deployments/base.toml`

Then run:

```bash
source .env
forge script script/SwapBaseWethUsdc.s.sol:SwapBaseWethUsdc \
  --rpc-url base \
  --broadcast \
  --private-key $PRIVATE_KEY
```

Note:
- `deployments/base.toml` must contain addresses from a real `--broadcast` deploy on Base.
- If it contains dry-run addresses, swap script reverts with `CONTRAPARTY_NOT_DEPLOYED`.

Behavior:
- Wraps ETH to WETH via `deposit()`.
- Approves Contraparty.
- Gets quote via `contraparty.quote(...)` with a 1,000,000 gas cap and computes `minAmountOut` from `SWAP_SLIPPAGE_BPS`.
- Calls `swap(WETH, USDC, amountIn, minAmountOut)`.
