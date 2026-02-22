# ContrapartyV2 Swap Execution Flow

This document describes the live `ContrapartyV2` execution flow (single full-order attempt sequence with second-price settlement).

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant CP as ContrapartyV2
    participant AMM1 as Top-scored AMM
    participant AMM2 as Next-scored AMM

    User->>CP: swap(tokenIn, tokenOut, amountIn, minOut, recipient, deadline)
    CP->>CP: validate deadline, pull tokenIn from user
    CP->>AMM1: quote(full amount)
    CP->>AMM2: quote(full amount)
    Note over CP: score = (quote - minOut) * penalty
    Note over CP: sort candidates by score desc

    CP->>CP: settlementOut = max(minOut, minOut + nextBestScore)
    CP->>CP: self-call try_fill_order(..., amm=winner, settlementOut, quotedOut)
    CP->>AMM1: approve(tokenIn, amountIn)
    CP->>AMM1: swap(tokenIn, tokenOut, amountIn, settlementOut)
    AMM1-->>CP: returns amountOut (must be >= settlementOut)
    CP->>AMM1: transferFrom(tokenOut, settlementOut)
    CP->>CP: revoke tokenIn approval

    alt winner execution failed
        CP->>CP: apply penalty (halve penalty score)
        CP->>CP: repeat with next candidate
    end

    CP->>User: refund leftover tokenIn (if any)
    CP->>recipient: transfer(tokenOut, settlementOut)
```

## V2-Specific Properties

- `quote()` returns the **second-highest raw bid** for the full input amount.
- `swap()` enforces user-provided `deadline`.
- Settlement uses second-price logic:
  - `settlementOut = max(minAmountOut, minAmountOut + secondBestScore)`
  - where `secondBestScore = (secondQuote - minAmountOut) * penalty / 1e18`
- The winner must execute at least `settlementOut`, and Contraparty pulls exactly `settlementOut` from the winner.
- If a candidate fails, the transaction does not revert immediately; Contraparty penalizes that AMM and tries the next one.
