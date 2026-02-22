# Counterparty Swap Execution Flow

This diagram explains the callback-based sub-order execution path used by the refactored `CounterpartyVyper` and Vyper Prop AMMs.

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant CP as CounterpartyVyper
    participant AMM as Prop AMM Adapter
    participant Pool as Uni/Aero Pool

    User->>CP: swap(tokenIn, tokenOut, amountIn, minAmountOut)
    CP->>User: transferFrom(tokenIn, amountIn)

    loop per sub-order
        CP->>AMM: quote(tokenIn, tokenOut, subAmount)
        Note over CP: rank AMMs by weighted score

        CP->>AMM: approve(tokenIn, subAmount)
        CP->>CP: tstore pending context
        CP->>AMM: swap(tokenIn, tokenOut, subAmount, quotedOut)

        AMM->>Pool: swap(..., to=AMM, data!=empty)
        Pool->>AMM: callback (uniswapV3SwapCallback / uniswapV2Call / hook)

        AMM->>CP: transfer(tokenOut, amountOut)
        AMM->>CP: counterpartyCallback()
        CP->>CP: validate tokenOut balance increase >= minOut
        CP->>AMM: transfer(tokenIn, subAmount)

        AMM->>Pool: repay tokenIn
        Pool-->>AMM: finalize swap
        AMM-->>CP: swap() returns amountOut

        CP->>CP: revoke approval (set allowance 0)
    end

    CP->>User: transfer(tokenOut, totalOut)
```

## Key Safety Properties

- Input token is released **only after** `Counterparty` verifies output-token balance increase.
- If callback settlement fails, the AMM swap reverts and the sub-order attempt is treated as failed.
- Per-attempt allowance is revoked after each candidate AMM attempt.
- Penalty is reduced on failures and slightly boosted (+1%, capped at 1e18) on better-than-quoted fills.
