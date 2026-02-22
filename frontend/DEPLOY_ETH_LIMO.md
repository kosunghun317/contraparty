# Deploy Frontend to IPNS + `.eth.limo`

This guide publishes the `frontend/` directory to IPFS, points an IPNS name at the latest CID, and serves it via ENS through `.eth.limo`.
With this flow, you update IPNS for each release and usually avoid changing ENS contenthash every time.

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

## 3. Create and publish an IPNS name

Create a dedicated IPNS key once:

```bash
ipfs key gen --type=rsa --size=2048 contraparty-frontend
```

Get the key ID (IPNS name, usually starts with `k51...`):

```bash
ipfs key list -l | grep contraparty-frontend
```

Publish the CID to that IPNS key:

```bash
ipfs name publish --key=contraparty-frontend /ipfs/<CID>
```

Verify:

```bash
ipfs name resolve /ipns/<IPNS_NAME>
```

## 4. Point ENS contenthash to IPNS

You need an ENS name you control, for example `yourname.eth`.

In ENS Manager:

1. Open `https://app.ens.domains`.
2. Select your name.
3. Go to `Records`.
4. Set `Content Hash` to your IPNS name (format: `ipns://<IPNS_NAME>`).
5. Save and confirm onchain.

You do this ENS update once (or when rotating IPNS key).

## 5. Access from browser

Once propagation completes, open:

- `https://yourname.eth.limo`

`.eth.limo` resolves ENS contenthash over HTTPS.

## 6. Updating (no ENS tx in normal case)

For updates:

1. Republish updated `frontend/` directory to get a new CID.
2. Publish new CID to the same IPNS name:
   `ipfs name publish --key=contraparty-frontend /ipfs/<NEW_CID>`
3. Re-open `https://yourname.eth.limo`.

As long as ENS still points to the same `ipns://<IPNS_NAME>`, no ENS onchain update is needed.

## Optional: direct IPFS gateways

You can also test directly:

- `https://ipfs.io/ipfs/<CID>`
- `https://cloudflare-ipfs.com/ipfs/<CID>`

And test via IPNS gateway form:

- `https://ipfs.io/ipns/<IPNS_NAME>`
