# Contraparty Frontend

## User app

- Path: `frontend/index.html`
- UX: minimal swap box (token in/out + amount in) with automatic quoting.
- Developer/integrator options are hidden from end users.
- UI direction adapted from zAMM frontend patterns.
- Wallet connection: injected wallet (`window.ethereum`) via `viem` wallet client in `frontend/wallet.js`.

## Source reference used for redesign

- `zamm.eth.limo` current IPFS CID: `bafkreihdpo35yvfi4vw4nr33yazmhaqrevlit7jsg22uilodub5ozfhm2e`
- Frontend repository: `https://github.com/zammdefi/zRouter` (see `dapp/index.html`)

## Configure quote backend and RPC

Set network config in `frontend/defaults.js`:

- `rpcUrl` / `rpcUrls` (public fallback RPCs)
- `cowChainId` (`1` for Ethereum, `8453` for Base)
- `supported` (`false` keeps chain visible but unselectable)
- token metadata

Read path behavior:
- Primary: injected wallet RPC (`window.ethereum`) when wallet chain matches selected chain.
- Fallback: public RPCs from `rpcUrls` (no private Alchemy endpoint embedded).

Quote flow is powered by CoW SDK `OrderBookApi.getQuote()` in `frontend/app.js`.
On Base, the app also checks:

- ElfomoFi quote contract `0xf0f0F0F0FB0d738452EfD03A28e8be14C76d5f73`
- Contraparty quote contract `0x0341F4282D10C1A130C21CE0BDcE82076951e819`

The frontend compares all available sources and picks the best executable quote.

Wallet connect logic is in `frontend/wallet.js`:

- Pure injected-wallet flow (no third-party wallet UI kit dependency).
- Button state is always rendered (`Connect Wallet`, `Connecting...`, or short address).

## Run locally

```bash
cd frontend
python3 -m http.server 8080
```

Open:

- Swap page: `http://localhost:8080`
