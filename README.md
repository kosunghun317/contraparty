# Contraparty Monorepo

This repository is the monorepo for Contraparty, a fully on-chain prop AMM router.
To Prop AMM operators: for integration, please contact to @wycfwycf via X or telegram DM.

## What Contraparty Does

Contraparty routes swaps across registered Prop AMMs using an on-chain second-price auction model:

- Prop AMMs submit bids in the form of quotes for the full order.
- The highest bidder wins execution.
- Settlement is based on the second-best quote (second-price clearing).

Contraparty does not currently take an explicit protocol fee. Instead, value is created by the spread between the first and second quote. That spread is shared between the winning Prop AMM and Contraparty. Right now, Contraparty's share is set to `0`, and this split is expected to change in future versions.

## Monorepo Layout

- `contracts/`: Vyper/Solidity contracts, Foundry tests, deployment and migration scripts.
- `frontend/`: user-facing application.
- `docs/`: project-level documentation.
