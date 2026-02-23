# Canonic MAOB Prop AMM Integration

Source: `contracts/src/CanonicPropAMM.vy`

## How Canonic MAOB Works

MAOB is a midpoint-anchored onchain order book with rung-based liquidity.

Conceptually:

- The market has a `baseToken` and `quoteToken`.
- A midpoint price (`getMidPrice`) acts as reference.
- Liquidity sits on discrete rungs (`bpsRungs`, `getRungState`) around midpoint.
- Taker execution consumes rung liquidity and pays taker fee (`takerFee / FEE_DENOM`).
- Market can be halted (`marketState`), in which case execution should be disabled.

In this repo's integration:

- `base -> quote` routing uses `sellBaseTargetIn`.
- `quote -> base` routing uses `buyBaseTargetIn`.

## `quote()` Implementation

`quote(token_in, token_out, amount_in)` does conservative pricing and returns `0` when uncertain.

Flow:

1. Determine direction via `_pair_mode`:
   - base->quote (`MODE_SELL_BASE_TO_QUOTE`)
   - quote->base (`MODE_BUY_QUOTE_TO_BASE`)
2. Reject unsupported pair, zero input, or halted market.
3. Compute directional quote:
   - `_quote_sell_base_to_quote(amount_in)`
   - `_quote_buy_quote_to_base(amount_in)`

### Sell Base -> Quote (`_quote_sell_base_to_quote`)

- Validates midpoint and scales (`quoteScale`, `baseScale`, `PRICE_SIGFIGS`).
- Enforces MAOB taker notional guard (`minQuoteTaker`) at midpoint.
- Iterates bid-side rung liquidity (`getRungState`) up to `MAX_RUNGS`.
- Computes fillable base against rung price and sums gross quote output.
- Applies taker fee and then safety haircut:
  - `quote_haircut_bps` (configurable, default `9999` = 0.01% haircut)

If full input cannot be covered by rung liquidity, returns `0`.

### Buy Base <- Quote (`_quote_buy_quote_to_base`)

- Requires `amount_in >= minQuoteTaker`.
- Iterates ask-side rungs and simulates fill from lower to higher rung.
- For each rung:
  - computes rung price from midpoint and rung bps
  - computes quote needed to consume full rung (ceil-rounded)
  - consumes full rung or partial rung based on remaining quote input
- Applies taker fee and then `quote_haircut_bps`.

## `swap()` Implementation

`swap(token_in, token_out, amount_in, min_amount_out)`:

1. Validates non-zero input/min-out and active market.
2. Validates direction and recomputes conservative quote.
3. Requires conservative quote `>= min_amount_out`.
4. Pulls `token_in` from caller (`Contraparty`).
5. Approves MAOB to spend input.
6. Calls MAOB taker method:
   - `sellBaseTargetIn(...)` for base->quote
   - `buyBaseTargetIn(...)` for quote->base
7. Requires returned `amount_out >= min_amount_out`.
8. Approves `token_out` to caller (`Contraparty`) for exact output.
9. Returns `amount_out`.

## Integration Contract Boundary with Contraparty

- Contraparty approves adapter for input and calls `swap`.
- Adapter executes MAOB taker path and returns actual output.
- Adapter makes output pullable by approving Contraparty.
- Contraparty pulls output via `transferFrom` and settles to end recipient.

## Admin / Operations

- `pull_accrued(token, amount, recipient)` for residual balances
- `set_quote_haircut_bps(new_bps)` to tune quote conservatism

## Why quote is conservative

The adapter intentionally underquotes when uncertain so Contraparty does not route on fragile estimates:

- market-halted check
- structural validation of midpoint/scales
- rung-by-rung liquidity checks
- taker fee deduction
- configurable haircut (default 0.01%) before returning quote
