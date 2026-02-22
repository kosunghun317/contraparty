# Prop AMM Integration Docs

This directory documents each Prop AMM adapter used by `Contraparty`.

- `contracts/docs/prop-amm-uniswap-v3.md`
- `contracts/docs/prop-amm-uniswap-v2.md`
- `contracts/docs/prop-amm-aerodrome.md`
- `contracts/docs/prop-amm-canonic-maob.md`

Each file explains:

- the venue model
- how `quote(token_in, token_out, amount_in)` is computed
- how `swap(token_in, token_out, amount_in, min_amount_out)` is executed
- how the adapter settles back to `Contraparty`
