# Aerodrome Prop AMM Integration

Source: `contracts/src/AerodromePropAMM.vy`

## Venue Model

This adapter integrates Aerodrome pools through the Aerodrome factory, evaluating both:

- volatile pool: `stable = false`
- stable pool: `stable = true`

## `quote()` Implementation

`quote(token_in, token_out, amount_in)`:

1. Calls `_best_pool(...)`.
2. `_best_pool` fetches volatile and stable pool addresses from factory.
3. For each pool, `_quote_pool` performs static `raw_call` to:
   - `getAmountOut(uint256,address)`
4. Chooses and returns the larger of volatile/stable quotes.
5. Returns `0` if neither pool yields a valid amount.

Failure handling:

- Missing pool address or failed `raw_call` returns `0` for that pool.

## `swap()` Implementation

`swap(token_in, token_out, amount_in, min_amount_out)`:

1. Recomputes best pool/quote using `_best_pool`.
2. Requires selected quote `>= min_amount_out`.
3. Pulls `token_in` from caller (`Contraparty`).
4. Transfers input token to selected pool.
5. Executes direct pool `swap(...)` with `to=self`.
6. Computes actual output by balance delta on `token_out`.
7. Requires output `>= min_amount_out`.
8. Approves `token_out` to caller (`Contraparty`) for exact output.
9. Returns `amount_out`.

## Integration Contract Boundary with Contraparty

- Contraparty provides input via allowance + `transferFrom`.
- Adapter performs venue swap and makes output pullable by Contraparty.
- Contraparty finalizes settlement by pulling `token_out`.

## Admin / Operations

- `pull_accrued(token, amount, recipient)` for residual balances
