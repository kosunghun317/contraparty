import { createWalletClient, custom, getAddress } from "https://esm.sh/viem@2.38.6?bundle";

const mount = document.getElementById("walletRoot");
const DISCONNECT_FLAG_KEY = "contraparty.walletDisconnected";

const state = {
  account: "",
  busy: false,
  pendingAction: "",
  manuallyDisconnected: readDisconnectFlag()
};
let walletBtn = null;

if (mount) {
  walletBtn = document.createElement("button");
  walletBtn.id = "walletBtn";
  walletBtn.className = "wallet-btn";
  walletBtn.type = "button";
  mount.replaceChildren(walletBtn);
  walletBtn.addEventListener("click", () => {
    if (state.busy) return;
    if (state.account) {
      void disconnectWallet();
      return;
    }
    void connectWallet();
  });

  renderWalletButton();
  wireWalletEvents();
  void hydrateWallet();
}

function shortAddress(address) {
  if (!address || typeof address !== "string") return "";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function readDisconnectFlag() {
  try {
    return window.localStorage.getItem(DISCONNECT_FLAG_KEY) === "1";
  } catch {
    return false;
  }
}

function writeDisconnectFlag(disconnected) {
  try {
    if (disconnected) {
      window.localStorage.setItem(DISCONNECT_FLAG_KEY, "1");
      return;
    }
    window.localStorage.removeItem(DISCONNECT_FLAG_KEY);
  } catch {
    // Ignore storage failures in restrictive browsing contexts.
  }
}

function normalizeAccount(raw) {
  const candidate = typeof raw === "string" ? raw : (raw && typeof raw === "object" && raw.address ? String(raw.address) : "");
  if (!candidate) return "";
  try {
    return getAddress(candidate);
  } catch {
    return "";
  }
}

function buttonLabel() {
  if (state.busy && state.pendingAction === "disconnect") return "Disconnecting...";
  if (state.busy) return "Connecting...";
  if (state.account) return shortAddress(state.account) || state.account;
  return "Connect Wallet";
}

function renderWalletButton() {
  if (!walletBtn) return;
  walletBtn.textContent = buttonLabel();
  walletBtn.title = state.account || "";
}

async function connectWallet() {
  if (!window.ethereum) {
    state.busy = false;
    state.pendingAction = "";
    renderWalletButton();
    if (walletBtn) walletBtn.textContent = "No Wallet";
    return;
  }

  state.pendingAction = "connect";
  state.busy = true;
  renderWalletButton();

  try {
    const walletClient = createWalletClient({ transport: custom(window.ethereum) });
    const addresses = await walletClient.requestAddresses();
    const connected = addresses && addresses.length > 0 ? addresses[0] : "";
    state.account = normalizeAccount(connected);
    state.manuallyDisconnected = false;
    writeDisconnectFlag(false);
  } catch {
    // Keep previous account on user rejection or transient wallet errors.
  } finally {
    state.busy = false;
    state.pendingAction = "";
    renderWalletButton();
  }
}

async function disconnectWallet() {
  state.pendingAction = "disconnect";
  state.busy = true;
  renderWalletButton();

  try {
    if (window.ethereum && typeof window.ethereum.request === "function") {
      await window.ethereum.request({
        method: "wallet_revokePermissions",
        params: [{ eth_accounts: {} }]
      });
    }
  } catch {
    // This RPC is optional and not widely supported.
  } finally {
    state.account = "";
    state.manuallyDisconnected = true;
    writeDisconnectFlag(true);
    state.busy = false;
    state.pendingAction = "";
    renderWalletButton();
  }
}

async function hydrateWallet() {
  if (!window.ethereum) return;
  if (state.manuallyDisconnected) {
    state.account = "";
    renderWalletButton();
    return;
  }
  try {
    const accounts = await window.ethereum.request({ method: "eth_accounts" });
    state.account = accounts && accounts.length > 0 ? normalizeAccount(accounts[0]) : "";
  } catch {
    state.account = "";
  } finally {
    renderWalletButton();
  }
}

function wireWalletEvents() {
  if (window.ethereum && typeof window.ethereum.on === "function" && !window.__contrapartyWalletBound) {
    window.ethereum.on("accountsChanged", (accounts) => {
      if (state.manuallyDisconnected) return;
      state.account = accounts && accounts.length > 0 ? normalizeAccount(accounts[0]) : "";
      state.busy = false;
      state.pendingAction = "";
      renderWalletButton();
    });
    window.ethereum.on("disconnect", () => {
      state.account = "";
      state.busy = false;
      state.pendingAction = "";
      state.manuallyDisconnected = true;
      writeDisconnectFlag(true);
      renderWalletButton();
    });
    window.__contrapartyWalletBound = true;
  }
}
