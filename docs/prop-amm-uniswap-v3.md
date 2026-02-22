# Uniswap V3 Prop AMM Integration

Source: `contracts/src/UniswapV3PropAMM.vy`

## Venue Model

This adapter integrates concentrated-liquidity V3 pools and uses an external quoter contract for read-only pricing.

Key design points:

- Pools are manually registered by owner (`register_pool`) and stored locally.
- The adapter does **not** scan the factory on every quote/swap.
- For a token pair, it evaluates only registered pools with matching pair key.

## `quote()` Implementation

`quote(token_in, token_out, amount_in)`:

1. Calls `_best_route(...)`.
2. `_best_route` iterates registered pools for the pair.
3. For each pool, `_quote_single_pool` calls `_quote_with_quoter`.
4. `_quote_with_quoter` performs static `raw_call` to quoter:
   - method: `quoteExactInputSingle((address,address,uint256,uint24,uint160))`
   - gas cap: `QUOTER_GAS_LIMIT`
5. Returns the highest successful quote, or `0` if no valid pool quote.

Failure handling:

- If quoter call fails/reverts/returns short data, that pool quote is treated as `0`.
- If no pool returns output, `quote()` returns `0`.

## `swap()` Implementation

`swap(token_in, token_out, amount_in, min_amount_out)`:

1. Re-computes best route and quote (`_best_route`) at execution time.
2. Requires best quote `>= min_amount_out`.
3. Pulls `token_in` from caller (`Contraparty`) via `transferFrom`.
4. Executes pool `swap(...)` with `recipient=self`.
5. Handles settlement in `uniswapV3SwapCallback(...)`:
   - validates callback sender is the selected pool
   - pays owed input token back to pool
   - records output amount received by adapter
6. After callback, requires output `>= min_amount_out`.
7. Approves `token_out` allowance to caller (`Contraparty`) for exact `amount_out`.
8. Returns `amount_out`.

## Integration Contract Boundary with Contraparty

- Contraparty approves `token_in` to adapter before calling `swap`.
- Adapter must return real `amount_out` and grant `token_out` allowance to Contraparty.
- Contraparty then pulls `token_out` via `transferFrom(adapter, contraparty, amount_out)`.

## Admin / Operations

- `register_pool(pool, fee)` / `remove_pool(pool)`
- `set_quoter(quoter)`
- `pull_accrued(token, amount, recipient)` for residual balances

## MegaETH Kumbaya Pools (Current Config)

These pools are currently wired in MegaETH deploy/test scripts:

- `0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22`
  - `token0 = 0x4200000000000000000000000000000000000006` (WETH)
  - `token1 = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7` (USDm)
  - `fee = 3000`
- `0x2809696F2e42eB452C32C3d0A2Dc540858C14125`
  - `token0 = 0x4200000000000000000000000000000000000006` (WETH)
  - `token1 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb` (USDT0)
  - `fee = 3000`
- `0xc1838B7807e5bd4D56EA630BA35Ac964CF72c9db`
  - `token0 = 0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072` (BTC.b)
  - `token1 = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7` (USDm)
  - `fee = 3000`
- `0x6c8E5D463a2473b1A8bcd87e1cEA2724203A1D8f`
  - `token0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb` (USDT0)
  - `token1 = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7` (USDm)
  - `fee = 100`
