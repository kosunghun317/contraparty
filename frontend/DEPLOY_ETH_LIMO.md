# Deploy Frontend to IPFS + `.eth.limo`

This guide publishes the `frontend/` directory to IPFS and serves it via ENS through `.eth.limo`.

## 1. Build assets

This frontend is static, so no build step is required.

## 2. Publish directory to IPFS

Using `ipfs` CLI:

```bash
cd frontend
ipfs add -r .
```

Copy the final directory CID (the last line).

Alternative using Pinata/Web3.Storage is also fine; you still need the directory CID.

## 3. Point ENS contenthash to the CID

You need an ENS name you control, for example `yourname.eth`.

In ENS Manager:

1. Open `https://app.ens.domains`.
2. Select your name.
3. Go to `Records`.
4. Set `Content Hash` to the IPFS CID (format like `ipfs://<CID>`).
5. Save and confirm onchain.

## 4. Access from browser

Once propagation completes, open:

- `https://yourname.eth.limo`

`.eth.limo` resolves ENS contenthash over HTTPS.

## 5. Updating

For updates:

1. Republish updated `frontend/` directory to get a new CID.
2. Update ENS contenthash to the new CID.
3. Re-open `https://yourname.eth.limo`.

## Optional: direct IPFS gateways

You can also test directly:

- `https://ipfs.io/ipfs/<CID>`
- `https://cloudflare-ipfs.com/ipfs/<CID>`
