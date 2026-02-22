# Uniswap V2 Prop AMM Integration

Source: `contracts/src/UniswapV2PropAMM.vy`

## Venue Model

This adapter integrates classic constant-product pools discovered through a V2 factory.

## `quote()` Implementation

`quote(token_in, token_out, amount_in)`:

1. Resolves pair via `factory.getPair(token_in, token_out)`.
2. Calls `_quote_pair(pair, token_in, token_out, amount_in)`.
3. `_quote_pair`:
   - reads `token0/token1` and reserves
   - maps reserves to in/out side
   - applies V2 formula with 0.3% fee constants:
     - `amount_in_with_fee = amount_in * 997`
     - `amount_out = (amount_in_with_fee * reserve_out) / (reserve_in * 1000 + amount_in_with_fee)`
4. Returns quote if valid, else `0`.

## `swap()` Implementation

`swap(token_in, token_out, amount_in, min_amount_out)`:

1. Re-quotes same pair via `_quote_pair`.
2. Requires quote `>= min_amount_out`.
3. Pulls `token_in` from caller (`Contraparty`).
4. Transfers `token_in` to pair.
5. Calls pair `swap(amount0Out, amount1Out, to=self, data="")`.
6. Measures adapter token_out balance delta as actual `amount_out`.
7. Requires `amount_out >= min_amount_out`.
8. Approves `token_out` allowance to caller (`Contraparty`) for exact output.
9. Returns `amount_out`.

## Integration Contract Boundary with Contraparty

- Contraparty supplies input via allowance + `transferFrom`.
- Adapter returns output amount and allows Contraparty to pull output token.
- Output settlement is pull-based (`transferFrom`) from adapter to Contraparty.

## Admin / Operations

- `pull_accrued(token, amount, recipient)` for residual balances
