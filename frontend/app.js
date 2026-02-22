import { APP_CONFIG, APP_VERSION } from "./defaults.js";
import {
  createPublicClient,
  createWalletClient,
  custom,
  fallback,
  formatUnits,
  getAddress,
  hexToString,
  http,
  isAddress,
  maxUint256,
  parseAbi,
  parseUnits,
  toHex
} from "https://esm.sh/viem@2.38.6?bundle";

const ERC20_METADATA_ABI = parseAbi([
  "function symbol() view returns (string)",
  "function name() view returns (string)",
  "function decimals() view returns (uint8)"
]);
const ERC20_METADATA_BYTES32_ABI = parseAbi([
  "function symbol() view returns (bytes32)",
  "function name() view returns (bytes32)",
  "function decimals() view returns (uint8)"
]);
const ELFOMO_QUOTE_ABI = parseAbi([
  "function getAmountOut(address fromToken, address toToken, uint256 fromAmount) view returns (uint256 toAmount)"
]);
const ELFOMO_SWAP_ABI = parseAbi([
  "function swap(address fromToken, address toToken, int256 specifiedAmount, uint256 limitAmount, address receiver, uint256 partnerId) returns (int256 amount0, int256 amount1)"
]);
const CONTRAPARTY_QUOTE_ABI = parseAbi([
  "function quote(address token_in, address token_out, uint256 amount_in) view returns (uint256)"
]);
const CONTRAPARTY_SWAP_ABI = parseAbi([
  "function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient) returns (uint256)"
]);
const ERC20_ALLOWANCE_ABI = parseAbi(["function allowance(address owner, address spender) view returns (uint256)"]);
const ERC20_BALANCE_ABI = parseAbi(["function balanceOf(address owner) view returns (uint256)"]);
const ERC20_APPROVE_ABI = parseAbi(["function approve(address spender, uint256 amount) returns (bool)"]);
const SLIPPAGE_PRESET_BPS = {
  "0.1": 10,
  "0.5": 50,
  "1": 100
};
const AUTO_SLIPPAGE_BPS = 50;
const QUOTE_REFRESH_MS = 30_000;
const FALLBACK_QUOTE_OWNER = "0x0000000000000000000000000000000000000001";
const NATIVE_TOKEN_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
const MAX_UINT256 = maxUint256;
const APP_CODE = "contraparty";
const COW_CHAIN_ID_MAINNET = 1;
const COW_CHAIN_ID_BASE = 8453;
const COW_VAULT_RELAYER_BY_CHAIN = {
  [COW_CHAIN_ID_MAINNET]: "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110",
  [COW_CHAIN_ID_BASE]: "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110"
};
const COW_QUOTE_URL_BY_CHAIN = {
  [COW_CHAIN_ID_MAINNET]: "https://api.cow.fi/mainnet/api/v1/quote",
  [COW_CHAIN_ID_BASE]: "https://api.cow.fi/base/api/v1/quote"
};
const EXPLORER_TX_BASE_BY_CHAIN = {
  [COW_CHAIN_ID_MAINNET]: "https://etherscan.io/tx/",
  [COW_CHAIN_ID_BASE]: "https://basescan.org/tx/",
  4326: "https://megaeth.blockscout.com/tx/",
  6342: "https://megaeth.blockscout.com/tx/"
};
const COW_SDK_MODULE_URL = "https://esm.sh/@cowprotocol/cow-sdk@7.3.5?bundle";
const COW_VIEM_ADAPTER_MODULE_URL = "https://esm.sh/@cowprotocol/sdk-viem-adapter@0.3.6?bundle";
const KYBER_API_BASE_URL = "https://aggregator-api.kyberswap.com";
const KYBER_CLIENT_ID = "contraparty";
const KYBER_CHAIN_SLUG_BY_ID = {
  1: "ethereum",
  8453: "base",
  4326: "megaeth"
};

const els = {
  networkChip: document.getElementById("networkChip"),
  fromTokenBtn: document.getElementById("fromTokenBtn"),
  fromBalanceValue: document.getElementById("fromBalanceValue"),
  fromMaxBtn: document.getElementById("fromMaxBtn"),
  fromHalfBtn: document.getElementById("fromHalfBtn"),
  fromQuarterBtn: document.getElementById("fromQuarterBtn"),
  toTokenBtn: document.getElementById("toTokenBtn"),
  fromAmount: document.getElementById("fromAmount"),
  toAmount: document.getElementById("toAmount"),
  swapSubmitBtn: document.getElementById("swapSubmitBtn"),
  flipBtn: document.getElementById("flipBtn"),
  quoteInfo: document.getElementById("quoteInfo"),
  routeInfo: document.getElementById("routeInfo"),
  minOutInfo: document.getElementById("minOutInfo"),
  advancedToggle: document.getElementById("advancedToggle"),
  advancedPanel: document.getElementById("advancedPanel"),
  slippageSelect: document.getElementById("slippageSelect"),
  slippageCustom: document.getElementById("slippageCustom"),
  recipientInput: document.getElementById("recipientInput"),
  status: document.getElementById("status"),
  appVersion: document.querySelector(".app-version"),
  tokenModal: document.getElementById("tokenModal"),
  closeModalBtn: document.getElementById("closeModalBtn"),
  tokenSearch: document.getElementById("tokenSearch"),
  tokenList: document.getElementById("tokenList"),
  chainModal: document.getElementById("chainModal"),
  closeChainModalBtn: document.getElementById("closeChainModalBtn"),
  chainList: document.getElementById("chainList")
};

const state = {
  activeNetworkKey: "",
  activeNetwork: null,
  tokens: [],
  tokenByAddress: new Map(),
  tokenBySymbol: new Map(),
  dynamicTokenCache: new Map(),
  pendingTokenLookups: new Set(),
  tokenLookupNonce: 0,
  fromToken: null,
  toToken: null,
  provider: null,
  providerKey: "",
  modalSide: "from",
  timer: null,
  quoteRefreshTimer: null,
  quoteNonce: 0,
  swapButtonNonce: 0,
  balanceNonce: 0,
  fromTokenBalance: 0n,
  swapBusy: false,
  latestQuote: null,
  approvalCache: new Map(),
  advancedOpen: false,
  slippageMode: "auto",
  customSlippage: "0.50",
  recipient: "",
  cowSwapDepsPromise: null,
  cowSwapDepsError: ""
};

function setStatus(msg) {
  els.status.textContent = msg;
}

function renderAppVersion() {
  if (!els.appVersion) return;
  els.appVersion.textContent = `version ${APP_VERSION}`;
}

function escapeHtml(input) {
  return String(input || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function getExplorerTxUrl(chainId, txHash) {
  const base = EXPLORER_TX_BASE_BY_CHAIN[Number(chainId || 0)] || "";
  if (!base) return "";
  const hash = String(txHash || "").trim();
  if (!/^0x[0-9a-fA-F]{64}$/.test(hash)) return "";
  return `${base}${hash}`;
}

function getBlockExplorerUrls(chainId) {
  const txBase = EXPLORER_TX_BASE_BY_CHAIN[Number(chainId || 0)] || "";
  if (!txBase) return [];

  try {
    const url = new URL(txBase);
    return [`${url.origin}`];
  } catch {
    const stripped = txBase.replace(/\/tx\/?$/i, "");
    return stripped ? [stripped] : [];
  }
}

function getNetworkConfigByChainId(chainId) {
  const target = Number(chainId || 0);
  if (target <= 0) return null;
  for (const config of Object.values(APP_CONFIG.networks)) {
    if (Number(config?.chainId || 0) === target) return config;
  }
  return null;
}

function setStatusTxLink(prefix, chainId, txHash) {
  const txUrl = getExplorerTxUrl(chainId, txHash);
  if (!txUrl) {
    setStatus(`${prefix} ${txHash}`);
    return;
  }

  const safePrefix = escapeHtml(prefix);
  const safeUrl = escapeHtml(txUrl);
  els.status.innerHTML = `${safePrefix} <a href="${safeUrl}" target="_blank" rel="noopener noreferrer">${safeUrl}</a>`;
}

function isUserRejectedError(error) {
  let current = error;
  let depth = 0;

  while (current && depth < 6) {
    if (typeof current === "string") {
      const text = current.toLowerCase();
      return text.includes("user rejected") || text.includes("rejected the request") || text.includes("user denied");
    }

    if (typeof current === "object") {
      if (Number(current.code) === 4001) return true;

      const name = typeof current.name === "string" ? current.name.toLowerCase() : "";
      if (name.includes("userrejected") || name.includes("rejectedrequest")) return true;

      const shortMessage = typeof current.shortMessage === "string" ? current.shortMessage.toLowerCase() : "";
      const message = typeof current.message === "string" ? current.message.toLowerCase() : "";
      const details = typeof current.details === "string" ? current.details.toLowerCase() : "";
      const merged = `${shortMessage}\n${message}\n${details}`;
      if (
        merged.includes("user rejected") ||
        merged.includes("rejected the request") ||
        merged.includes("user denied") ||
        merged.includes("denied transaction signature") ||
        merged.includes("request rejected")
      ) {
        return true;
      }

      current = current.cause;
      depth += 1;
      continue;
    }

    break;
  }

  return false;
}

function errorMessage(error, fallback = "Request failed.") {
  if (!error) return fallback;

  if (typeof error === "string") {
    const trimmed = error.trim();
    return trimmed || fallback;
  }

  if (typeof error === "object") {
    if (typeof error.shortMessage === "string" && error.shortMessage.trim()) {
      return error.shortMessage.trim();
    }
    if (typeof error.message === "string" && error.message.trim()) {
      return error.message.trim();
    }
  }

  return fallback;
}

function setSwapButton(label, disabled) {
  els.swapSubmitBtn.textContent = label;
  els.swapSubmitBtn.disabled = Boolean(disabled);
}

function setSwapBusy(label) {
  state.swapBusy = true;
  setSwapButton(label, true);
}

function clearSwapBusy() {
  state.swapBusy = false;
}

function invalidateLatestQuote() {
  state.latestQuote = null;
}

function isQuoteStale(quote) {
  if (!quote) return true;
  if (quote.networkKey !== state.activeNetworkKey) return true;
  if (quote.fromToken.toLowerCase() !== state.fromToken.address.toLowerCase()) return true;
  if (quote.toToken.toLowerCase() !== state.toToken.address.toLowerCase()) return true;

  try {
    const liveAmountIn = parseUnits(els.fromAmount.value.trim(), state.fromToken.decimals);
    return liveAmountIn !== quote.amountIn;
  } catch {
    return true;
  }
}

async function getWalletAccount(requestAccess = false) {
  if (!window.ethereum || typeof window.ethereum.request !== "function") return "";

  try {
    const method = requestAccess ? "eth_requestAccounts" : "eth_accounts";
    const accounts = await window.ethereum.request({ method });
    if (!accounts || accounts.length === 0) return "";
    return normalizeAddress(accounts[0]);
  } catch {
    return "";
  }
}

async function getWalletChainId() {
  if (!window.ethereum || typeof window.ethereum.request !== "function") return 0;

  try {
    const chainHex = await window.ethereum.request({ method: "eth_chainId" });
    if (typeof chainHex !== "string") return 0;
    return Number.parseInt(chainHex, 16);
  } catch {
    return 0;
  }
}

function getWalletChainIdSync() {
  const chainHex = window.ethereum && typeof window.ethereum.chainId === "string" ? window.ethereum.chainId : "";
  if (!/^0x[0-9a-fA-F]+$/.test(chainHex)) return 0;
  const parsed = Number.parseInt(chainHex, 16);
  return Number.isFinite(parsed) ? parsed : 0;
}

function getWalletClient(account) {
  if (!window.ethereum) {
    throw new Error("Wallet provider not found.");
  }

  const chain = buildViemChain(state.activeNetworkKey, state.activeNetwork);
  if (!chain) {
    throw new Error("Active network is not configured.");
  }

  return createWalletClient({
    account,
    chain,
    transport: custom(window.ethereum)
  });
}

async function ensureWalletChain(chainId) {
  if (!window.ethereum || typeof window.ethereum.request !== "function") {
    throw new Error("Wallet provider not found.");
  }

  const targetChainId = Number(chainId || 0);
  if (targetChainId <= 0) {
    throw new Error("Invalid chain id.");
  }

  const targetConfig = getNetworkConfigByChainId(targetChainId);
  const targetRpcUrls = getNetworkRpcUrls(targetConfig || {});
  const targetExplorerUrls = getBlockExplorerUrls(targetChainId);
  const targetChainHex = toHex(chainId);

  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: targetChainHex }]
    });
  } catch (error) {
    if (error && error.code === 4902) {
      if (!targetConfig || targetRpcUrls.length === 0) {
        throw new Error("Target chain is not available in wallet.");
      }

      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [
          {
            chainId: targetChainHex,
            chainName: String(targetConfig.label || `Chain ${targetChainId}`),
            nativeCurrency: {
              name: "Ether",
              symbol: "ETH",
              decimals: 18
            },
            rpcUrls: targetRpcUrls,
            ...(targetExplorerUrls.length > 0 ? { blockExplorerUrls: targetExplorerUrls } : {})
          }
        ]
      });

      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: targetChainHex }]
      });
      return;
    }
    throw error;
  }
}

function hasConfiguredQuoteBackend(config) {
  if (!config || config.supported === false) return false;

  const cowChainId = Number(config.cowChainId || 0);
  const hasCow = cowChainId > 0 && Boolean(getCowQuoteUrl(cowChainId));
  const hasElfomo = Number(config.chainId || 0) === COW_CHAIN_ID_BASE && isAddress(config.elfomoQuoteContract || "");
  const hasContraparty = isAddress(config.contrapartyQuoteContract || "");
  const hasKyber = Boolean(getKyberChainSlug(config.chainId));
  return hasCow || hasElfomo || hasContraparty || hasKyber;
}

function isNetworkSupported(config) {
  return Boolean(config && config.supported !== false && hasConfiguredQuoteBackend(config));
}

function firstSupportedNetworkKey() {
  for (const [key, cfg] of Object.entries(APP_CONFIG.networks)) {
    if (isNetworkSupported(cfg)) return key;
  }
  return APP_CONFIG.defaultNetwork;
}

function pickNetwork() {
  const hashRoute = parseHashRoute();
  if (hashRoute.chainId > 0) {
    for (const [key, cfg] of Object.entries(APP_CONFIG.networks)) {
      if (cfg.chainId === hashRoute.chainId && isNetworkSupported(cfg)) return key;
    }
  }

  const params = new URLSearchParams(window.location.search);
  const networkParam = (params.get("network") || "").toLowerCase();
  if (networkParam && APP_CONFIG.networks[networkParam] && isNetworkSupported(APP_CONFIG.networks[networkParam])) {
    return networkParam;
  }

  if (isNetworkSupported(APP_CONFIG.networks[APP_CONFIG.defaultNetwork])) {
    return APP_CONFIG.defaultNetwork;
  }

  return firstSupportedNetworkKey();
}

function parseHashRoute() {
  const raw = window.location.hash.replace(/^#\/?/, "");
  if (!raw) return { chainId: 0, tokenIn: "", tokenOut: "" };

  const parts = raw.split("/").filter(Boolean);
  let chainId = 0;
  if (parts.length > 0) {
    const parsedChainId = Number(parts[0]);
    if (Number.isFinite(parsedChainId) && parsedChainId > 0) {
      chainId = Math.trunc(parsedChainId);
    }
  }
  const swapIdx = parts.indexOf("swap");
  if (swapIdx === -1) return { chainId, tokenIn: "", tokenOut: "" };

  return {
    chainId,
    tokenIn: (parts[swapIdx + 1] || "").toLowerCase(),
    tokenOut: (parts[swapIdx + 2] || "").toLowerCase()
  };
}

function shortAddress(address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function shortHash(hash) {
  if (!hash || typeof hash !== "string" || hash.length < 12) return hash || "";
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}

function formatClockTime(date = new Date()) {
  try {
    return date.toLocaleTimeString([], { hour12: false });
  } catch {
    return date.toTimeString().slice(0, 8);
  }
}

function normalizeAddress(address) {
  try {
    return getAddress(address || "");
  } catch {
    return "";
  }
}

function getKyberChainSlug(chainId) {
  return KYBER_CHAIN_SLUG_BY_ID[Number(chainId || 0)] || "";
}

function parseBigIntLike(value) {
  if (typeof value === "bigint") return value;
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) return BigInt(Math.trunc(value));
  if (typeof value !== "string") return 0n;

  const raw = value.trim();
  if (!raw) return 0n;

  try {
    if (/^0x[0-9a-fA-F]+$/.test(raw)) return BigInt(raw);
    if (/^\d+$/.test(raw)) return BigInt(raw);
  } catch {
    return 0n;
  }

  return 0n;
}

function getNetworkRpcUrls(config) {
  const urls = [];
  const seen = new Set();
  const pushUrl = (value) => {
    const url = typeof value === "string" ? value.trim() : "";
    if (!url || seen.has(url)) return;
    seen.add(url);
    urls.push(url);
  };

  if (config && Array.isArray(config.rpcUrls)) {
    config.rpcUrls.forEach((url) => pushUrl(url));
  }
  if (config && typeof config.rpcUrl === "string") {
    pushUrl(config.rpcUrl);
  }

  return urls;
}

function buildViemChain(networkKey, config) {
  const rpcUrls = getNetworkRpcUrls(config);
  if (!config || rpcUrls.length === 0 || !config.chainId) return null;
  const primaryRpcUrl = rpcUrls[0];
  return {
    id: Number(config.chainId),
    name: String(config.label || `Chain ${config.chainId}`),
    network: String(networkKey || `chain-${config.chainId}`),
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18
    },
    rpcUrls: {
      default: { http: [primaryRpcUrl] },
      public: { http: [primaryRpcUrl] }
    }
  };
}

function formatBalanceDisplay(amount, decimals) {
  try {
    const normalized = amount < 0n ? 0n : amount;
    const raw = formatUnits(normalized, decimals);
    const [whole, fractionRaw = ""] = raw.split(".");
    const fraction = fractionRaw.slice(0, 6).replace(/0+$/, "");
    return fraction ? `${whole}.${fraction}` : whole;
  } catch {
    return "0";
  }
}

function setBalanceActionsEnabled(enabled) {
  const disabled = !enabled;
  els.fromMaxBtn.disabled = disabled;
  els.fromHalfBtn.disabled = disabled;
  els.fromQuarterBtn.disabled = disabled;
}

function renderFromBalance(connected, loading = false) {
  if (!connected) {
    state.fromTokenBalance = 0n;
    els.fromBalanceValue.textContent = "Balance: -";
    setBalanceActionsEnabled(false);
    return;
  }

  if (loading) {
    els.fromBalanceValue.textContent = "Balance: ...";
    setBalanceActionsEnabled(false);
    return;
  }

  els.fromBalanceValue.textContent = `Balance: ${formatBalanceDisplay(state.fromTokenBalance, state.fromToken.decimals)}`;
  setBalanceActionsEnabled(state.fromTokenBalance > 0n);
}

async function readTokenBalance(client, tokenAddress, account) {
  if (isNativeTokenAddress(tokenAddress)) {
    return client.getBalance({ address: account });
  }
  return client.readContract({
    address: tokenAddress,
    abi: ERC20_BALANCE_ABI,
    functionName: "balanceOf",
    args: [account]
  });
}

async function refreshFromTokenBalance() {
  const requestId = ++state.balanceNonce;
  const networkKey = state.activeNetworkKey;
  const tokenAddress = state.fromToken?.address?.toLowerCase() || "";
  const account = await getWalletAccount(false);

  if (requestId !== state.balanceNonce) return;
  if (networkKey !== state.activeNetworkKey) return;
  if (tokenAddress !== (state.fromToken?.address?.toLowerCase() || "")) return;

  if (!account || !state.fromToken) {
    renderFromBalance(false);
    return;
  }

  renderFromBalance(true, true);

  try {
    const provider = getProvider();
    const balance = await readTokenBalance(provider, state.fromToken.address, account);

    if (requestId !== state.balanceNonce) return;
    if (networkKey !== state.activeNetworkKey) return;
    if (tokenAddress !== (state.fromToken?.address?.toLowerCase() || "")) return;

    state.fromTokenBalance = balance > 0n ? balance : 0n;
    renderFromBalance(true, false);
  } catch {
    try {
      const walletChainId = await getWalletChainId();
      if (walletChainId === state.activeNetwork.chainId && window.ethereum) {
        const chain = buildViemChain(state.activeNetworkKey, state.activeNetwork);
        if (chain) {
          const walletReadClient = createPublicClient({
            chain,
            transport: custom(window.ethereum)
          });
          const walletBalance = await readTokenBalance(walletReadClient, state.fromToken.address, account);

          if (requestId !== state.balanceNonce) return;
          if (networkKey !== state.activeNetworkKey) return;
          if (tokenAddress !== (state.fromToken?.address?.toLowerCase() || "")) return;

          state.fromTokenBalance = walletBalance > 0n ? walletBalance : 0n;
          renderFromBalance(true, false);
          return;
        }
      }
    } catch {
      // Keep n/a fallback below if wallet-read fallback also fails.
    }

    if (requestId !== state.balanceNonce) return;
    if (networkKey !== state.activeNetworkKey) return;
    if (tokenAddress !== (state.fromToken?.address?.toLowerCase() || "")) return;
    els.fromBalanceValue.textContent = "Balance: n/a";
    setBalanceActionsEnabled(false);
  }
}

function fillFromAmountByBps(bps) {
  if (!Number.isFinite(bps) || bps <= 0) return;
  if (state.fromTokenBalance <= 0n) {
    setStatus("No balance available for selected token.");
    return;
  }

  let fillAmount = (state.fromTokenBalance * BigInt(Math.trunc(bps))) / 10_000n;
  if (fillAmount === 0n) fillAmount = state.fromTokenBalance;

  els.fromAmount.value = formatUnits(fillAmount, state.fromToken.decimals);
  scheduleQuote(0);
}

function isAddressQuery(input) {
  return /^0x[a-fA-F0-9]{40}$/.test((input || "").trim());
}

function updateNetworkChip() {
  els.networkChip.textContent = state.activeNetwork.label;
}

function renderTokenButtons() {
  els.fromTokenBtn.textContent = state.fromToken.symbol;
  els.toTokenBtn.textContent = state.toToken.symbol;
}

function buildTokenMaps(tokens) {
  state.tokenByAddress = new Map();
  state.tokenBySymbol = new Map();

  for (const token of tokens) {
    state.tokenByAddress.set(token.address.toLowerCase(), token);
    state.tokenBySymbol.set(token.symbol.toLowerCase(), token);
  }
}

function upsertToken(token) {
  const normalized = normalizeAddress(token.address);
  if (!normalized) return null;
  const lower = normalized.toLowerCase();
  if (state.tokenByAddress.has(lower)) return state.tokenByAddress.get(lower);

  const merged = {
    symbol: String(token.symbol || "").trim(),
    name: String(token.name || token.symbol || "").trim(),
    address: normalized,
    decimals: Number(token.decimals)
  };

  state.tokens.push(merged);
  state.tokenByAddress.set(lower, merged);
  state.tokenBySymbol.set(merged.symbol.toLowerCase(), merged);
  return merged;
}

function tokenFromRef(ref, fallbackSymbol) {
  const normalized = (ref || "").trim().toLowerCase();
  if (normalized.startsWith("0x")) {
    const byAddress = state.tokenByAddress.get(normalized);
    if (byAddress) return byAddress;
  }

  if (normalized) {
    const bySymbol = state.tokenBySymbol.get(normalized);
    if (bySymbol) return bySymbol;
  }

  const fallback = state.tokenBySymbol.get(fallbackSymbol.toLowerCase());
  if (fallback) return fallback;
  return state.tokens[0];
}

function syncHashRoute() {
  const path = `#/` + state.activeNetwork.chainId + `/swap/${state.fromToken.symbol}/${state.toToken.address}`;
  if (window.location.hash !== path) {
    history.replaceState({}, "", `${window.location.pathname}${window.location.search}${path}`);
  }
}

function setQuoteHidden(hidden) {
  els.quoteInfo.hidden = hidden;
}

function clearQuote(message = "") {
  invalidateLatestQuote();
  els.toAmount.value = "";
  els.routeInfo.textContent = "-";
  els.minOutInfo.textContent = "-";
  setQuoteHidden(true);
  if (message) setStatus(message);
  if (!state.swapBusy) {
    void refreshSwapButtonState();
  }
}

function toggleAdvanced(force) {
  state.advancedOpen = typeof force === "boolean" ? force : !state.advancedOpen;
  els.advancedPanel.hidden = !state.advancedOpen;
  els.advancedToggle.setAttribute("aria-expanded", state.advancedOpen ? "true" : "false");
  els.advancedToggle.textContent = `Advanced Options ${state.advancedOpen ? "▴" : "▾"}`;
}

function syncCustomSlippageInput() {
  const isCustom = state.slippageMode === "custom";
  els.slippageCustom.hidden = !isCustom;
  els.slippageCustom.disabled = !isCustom;
}

function parseCustomSlippageToBps(raw) {
  const clean = String(raw || "").trim();
  if (!/^\d+(\.\d{0,2})?$/.test(clean)) return null;
  const value = Number(clean);
  if (!Number.isFinite(value) || value < 0 || value > 50) return null;
  return Math.round(value * 100);
}

function slippageLabelFromBps(bps) {
  if (!Number.isInteger(bps) || bps < 0) return "0%";
  const pct = bps / 100;
  if (Number.isInteger(pct)) return `${pct}%`;
  if (Number.isInteger(pct * 10)) return `${pct.toFixed(1)}%`;
  return `${pct.toFixed(2)}%`;
}

function resolveSlippageConfig() {
  if (state.slippageMode === "auto") {
    return { bps: AUTO_SLIPPAGE_BPS, label: `Auto (${slippageLabelFromBps(AUTO_SLIPPAGE_BPS)})`, warning: "" };
  }

  if (state.slippageMode === "custom") {
    const bps = parseCustomSlippageToBps(state.customSlippage);
    if (bps === null) {
      return {
        bps: AUTO_SLIPPAGE_BPS,
        label: `Auto (${slippageLabelFromBps(AUTO_SLIPPAGE_BPS)})`,
        warning: "Custom slippage must be a number between 0 and 50 with up to 2 decimals."
      };
    }
    return { bps, label: slippageLabelFromBps(bps), warning: "" };
  }

  const preset = SLIPPAGE_PRESET_BPS[state.slippageMode];
  if (!preset) {
    return { bps: AUTO_SLIPPAGE_BPS, label: `Auto (${slippageLabelFromBps(AUTO_SLIPPAGE_BPS)})`, warning: "" };
  }
  return { bps: preset, label: slippageLabelFromBps(preset), warning: "" };
}

function validateRecipient(raw) {
  const clean = String(raw || "").trim();
  if (!clean) return { value: "", valid: true };

  try {
    return { value: getAddress(clean), valid: true };
  } catch {
    return { value: clean, valid: false };
  }
}

function getCowChainId() {
  const chainId = Number(state.activeNetwork?.cowChainId || 0);
  if (chainId === COW_CHAIN_ID_MAINNET) return COW_CHAIN_ID_MAINNET;
  if (chainId === COW_CHAIN_ID_BASE) return COW_CHAIN_ID_BASE;
  return 0;
}

function getProvider() {
  const rpcUrls = getNetworkRpcUrls(state.activeNetwork);
  const activeChainId = Number(state.activeNetwork?.chainId || 0);
  const walletChainId = getWalletChainIdSync();
  const walletRpcUsable = Boolean(window.ethereum && walletChainId > 0 && walletChainId === activeChainId);
  const key = `${state.activeNetworkKey}:${walletRpcUsable ? "wallet" : "public"}:${walletChainId}:${rpcUrls.join("|")}`;
  if (state.provider && state.providerKey === key) return state.provider;

  const chain = buildViemChain(state.activeNetworkKey, state.activeNetwork);
  if (!chain) {
    throw new Error("Active network is not configured.");
  }

  const publicTransports = rpcUrls.map((url) =>
    http(url, {
      timeout: 8_000,
      retryCount: 1,
      retryDelay: 150
    })
  );
  let transport = publicTransports.length > 1 ? fallback(publicTransports) : publicTransports[0];
  if (walletRpcUsable) {
    const transports = [custom(window.ethereum), ...publicTransports];
    transport = fallback(transports);
  }

  state.provider = createPublicClient({
    chain,
    transport
  });
  state.providerKey = key;
  return state.provider;
}

function getCowQuoteUrl(cowChainId) {
  if (!cowChainId) return "";
  return COW_QUOTE_URL_BY_CHAIN[cowChainId] || "";
}

function getCowVaultRelayerAddress(cowChainId) {
  if (!cowChainId) return "";
  return normalizeAddress(COW_VAULT_RELAYER_BY_CHAIN[cowChainId] || "");
}

async function quoteCow(cowChainId, payload) {
  const endpoint = getCowQuoteUrl(cowChainId);
  if (!endpoint) return 0n;

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) return 0n;
    const data = await response.json();
    const amount = data && data.quote && data.quote.buyAmount ? BigInt(data.quote.buyAmount) : 0n;
    return amount > 0n ? amount : 0n;
  } catch {
    return 0n;
  }
}

async function loadCowSwapDeps() {
  if (state.cowSwapDepsPromise) return state.cowSwapDepsPromise;

  state.cowSwapDepsPromise = Promise.all([import(COW_SDK_MODULE_URL), import(COW_VIEM_ADAPTER_MODULE_URL)])
    .then(([cowSdkModule, cowAdapterModule]) => {
      const TradingSdk = cowSdkModule?.TradingSdk;
      const ViemAdapter = cowAdapterModule?.ViemAdapter;
      if (typeof TradingSdk !== "function" || typeof ViemAdapter !== "function") {
        throw new Error("Unable to load CoW swap dependencies.");
      }
      state.cowSwapDepsError = "";
      return { TradingSdk, ViemAdapter };
    })
    .catch((error) => {
      state.cowSwapDepsPromise = null;
      state.cowSwapDepsError = error?.message || String(error);
      throw error;
    });

  return state.cowSwapDepsPromise;
}

function isNativeTokenAddress(address) {
  return String(address || "").toLowerCase() === NATIVE_TOKEN_ADDRESS.toLowerCase();
}

function getQuoteSpender(quote) {
  if (!quote) return "";
  if (quote.spender) return normalizeAddress(quote.spender);

  if (quote.source === "elfomo") {
    return normalizeAddress(state.activeNetwork?.elfomoQuoteContract || "");
  }

  if (quote.source === "cow") {
    const cowChainId = Number(quote.cowChainId || 0) || getCowChainId();
    if (!cowChainId) return "";
    return getCowVaultRelayerAddress(cowChainId);
  }

  if (quote.source === "contraparty") {
    return normalizeAddress(state.activeNetwork?.contrapartyQuoteContract || "");
  }

  if (quote.source === "kyber") {
    return normalizeAddress(quote.spender || "");
  }

  return "";
}

function resolveExecutionRecipient(account) {
  const recipientConfig = validateRecipient(state.recipient);
  if (recipientConfig.valid && recipientConfig.value) return recipientConfig.value;
  return account;
}

function approvalCacheKey(chainId, owner, token, spender) {
  const chain = Number(chainId || 0);
  const ownerAddress = normalizeAddress(owner || "").toLowerCase();
  const tokenAddress = normalizeAddress(token || "").toLowerCase();
  const spenderAddress = normalizeAddress(spender || "").toLowerCase();
  if (!chain || !ownerAddress || !tokenAddress || !spenderAddress) return "";
  return `${chain}:${ownerAddress}:${tokenAddress}:${spenderAddress}`;
}

async function getApprovalState(owner, quote) {
  const spender = getQuoteSpender(quote);
  if (!owner || !quote || isNativeTokenAddress(quote.fromToken)) {
    return {
      spender,
      allowance: quote?.amountIn || 0n,
      needsApproval: false
    };
  }

  const cacheKey = approvalCacheKey(state.activeNetwork?.chainId, owner, quote.fromToken, spender);
  const cachedAllowance = cacheKey ? state.approvalCache.get(cacheKey) || 0n : 0n;
  if (cachedAllowance >= quote.amountIn) {
    return {
      spender,
      allowance: cachedAllowance,
      needsApproval: false
    };
  }

  if (!spender) {
    return {
      spender: "",
      allowance: 0n,
      needsApproval: true
    };
  }

  try {
    const allowance = await getProvider().readContract({
      address: quote.fromToken,
      abi: ERC20_ALLOWANCE_ABI,
      functionName: "allowance",
      args: [owner, spender]
    });

    if (cacheKey) {
      state.approvalCache.set(cacheKey, allowance);
    }

    return {
      spender,
      allowance,
      needsApproval: allowance < quote.amountIn
    };
  } catch {
    if (cachedAllowance >= quote.amountIn) {
      return {
        spender,
        allowance: cachedAllowance,
        needsApproval: false
      };
    }

    return {
      spender,
      allowance: 0n,
      needsApproval: true
    };
  }
}

async function refreshSwapButtonState() {
  const requestId = ++state.swapButtonNonce;
  if (state.swapBusy) return;

  const amountRaw = els.fromAmount.value.trim();
  if (!amountRaw) {
    setSwapButton("Swap", true);
    return;
  }

  let parsedAmount = 0n;
  try {
    parsedAmount = parseUnits(amountRaw, state.fromToken.decimals);
  } catch {
    setSwapButton("Swap", true);
    return;
  }

  if (parsedAmount <= 0n) {
    setSwapButton("Swap", true);
    return;
  }

  if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) {
    setSwapButton("Swap", true);
    return;
  }

  const recipientConfig = validateRecipient(state.recipient);
  if (!recipientConfig.valid) {
    setSwapButton("Fix Recipient", true);
    return;
  }

  const quote = state.latestQuote;
  if (!quote || isQuoteStale(quote) || quote.quotedOut <= 0n) {
    setSwapButton("Get Quote", false);
    return;
  }

  if (quote.executable === false) {
    setSwapButton("Route Unavailable", true);
    return;
  }

  const account = await getWalletAccount(false);
  if (requestId !== state.swapButtonNonce || state.swapBusy) return;

  if (!account) {
    setSwapButton("Connect Wallet", false);
    return;
  }

  const walletChainId = await getWalletChainId();
  if (requestId !== state.swapButtonNonce || state.swapBusy) return;

  if (walletChainId > 0 && walletChainId !== state.activeNetwork.chainId) {
    setSwapButton("Switch Chain", false);
    return;
  }

  const approvalState = await getApprovalState(account, quote);
  if (requestId !== state.swapButtonNonce || state.swapBusy) return;

  setSwapButton(approvalState.needsApproval ? "Approve" : "Swap", false);
}

async function resolveQuoteOwner(recipientConfig) {
  if (recipientConfig.valid && recipientConfig.value) return recipientConfig.value;
  if (!window.ethereum || typeof window.ethereum.request !== "function") return FALLBACK_QUOTE_OWNER;

  try {
    const accounts = await window.ethereum.request({ method: "eth_accounts" });
    if (accounts && accounts.length > 0) {
      const normalized = normalizeAddress(accounts[0]);
      if (normalized) return normalized;
    }
  } catch {
    // Fallback owner is used when wallet account lookup is unavailable.
  }

  return FALLBACK_QUOTE_OWNER;
}

async function quoteElfomo(provider, quoteContract, tokenIn, tokenOut, amountIn) {
  if (!isAddress(quoteContract)) return 0n;
  try {
    const amountOut = await provider.readContract({
      address: quoteContract,
      abi: ELFOMO_QUOTE_ABI,
      functionName: "getAmountOut",
      args: [tokenIn, tokenOut, amountIn]
    });
    return amountOut > 0n ? amountOut : 0n;
  } catch {
    return 0n;
  }
}

async function quoteContraparty(provider, quoteContract, tokenIn, tokenOut, amountIn) {
  if (!isAddress(quoteContract)) return 0n;
  try {
    const amountOut = await provider.readContract({
      address: quoteContract,
      abi: CONTRAPARTY_QUOTE_ABI,
      functionName: "quote",
      args: [tokenIn, tokenOut, amountIn]
    });
    return amountOut > 0n ? amountOut : 0n;
  } catch {
    return 0n;
  }
}

async function quoteKyber(chainSlug, tokenIn, tokenOut, amountIn) {
  if (!chainSlug) return null;
  const params = new URLSearchParams({
    tokenIn,
    tokenOut,
    amountIn: amountIn.toString()
  });

  try {
    const response = await fetch(`${KYBER_API_BASE_URL}/${chainSlug}/api/v1/routes?${params.toString()}`, {
      headers: {
        "x-client-id": KYBER_CLIENT_ID
      }
    });
    if (!response.ok) return null;

    const payload = await response.json();
    const data = payload?.data || {};
    const routeSummary = data.routeSummary || null;
    const routerAddress = normalizeAddress(data.routerAddress || "");
    const quotedOut = parseBigIntLike(routeSummary?.amountOut);

    if (!routeSummary || !routerAddress || quotedOut <= 0n) return null;
    return {
      quotedOut,
      routerAddress,
      routeSummary
    };
  } catch {
    return null;
  }
}

function decodeBytes32Text(value) {
  try {
    return hexToString(value, { size: 32 }).replace(/\0/g, "").trim();
  } catch {
    return "";
  }
}

async function lookupTokenMetadata(address) {
  const normalized = normalizeAddress(address);
  if (!normalized) return;
  const lower = normalized.toLowerCase();

  if (state.dynamicTokenCache.has(lower) || state.pendingTokenLookups.has(lower)) return;
  state.pendingTokenLookups.add(lower);
  const nonce = ++state.tokenLookupNonce;

  try {
    const provider = getProvider();
    const decimalsRaw = await provider.readContract({
      address: normalized,
      abi: ERC20_METADATA_ABI,
      functionName: "decimals"
    });

    let symbol = "";
    let name = "";

    try {
      const symbolRaw = await provider.readContract({
        address: normalized,
        abi: ERC20_METADATA_ABI,
        functionName: "symbol"
      });
      symbol = String(symbolRaw || "").replace(/\0/g, "").trim();
    } catch {
      const symbolRaw = await provider.readContract({
        address: normalized,
        abi: ERC20_METADATA_BYTES32_ABI,
        functionName: "symbol"
      });
      symbol = decodeBytes32Text(symbolRaw);
    }

    try {
      const nameRaw = await provider.readContract({
        address: normalized,
        abi: ERC20_METADATA_ABI,
        functionName: "name"
      });
      name = String(nameRaw || "").replace(/\0/g, "").trim();
    } catch {
      const nameRaw = await provider.readContract({
        address: normalized,
        abi: ERC20_METADATA_BYTES32_ABI,
        functionName: "name"
      });
      name = decodeBytes32Text(nameRaw);
    }

    const decimals = Number(decimalsRaw);

    if (!symbol || !Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
      throw new Error("invalid token metadata");
    }

    state.dynamicTokenCache.set(lower, {
      symbol,
      name: name || symbol,
      address: normalized,
      decimals
    });
  } catch {
    state.dynamicTokenCache.set(lower, null);
  } finally {
    state.pendingTokenLookups.delete(lower);
    if (nonce <= state.tokenLookupNonce && !els.tokenModal.hidden) {
      renderTokenList(els.tokenSearch.value);
    }
  }
}

async function runQuote() {
  const requestId = ++state.quoteNonce;
  const slippageConfig = resolveSlippageConfig();
  const recipientConfig = validateRecipient(state.recipient);

  const amountRaw = els.fromAmount.value.trim();
  if (!amountRaw) {
    clearQuote("Type an amount to get started.");
    return;
  }

  if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) {
    clearQuote("Select different tokens.");
    return;
  }

  let amountIn;
  try {
    amountIn = parseUnits(amountRaw, state.fromToken.decimals);
  } catch {
    clearQuote("Amount format is invalid.");
    return;
  }

  if (amountIn <= 0n) {
    clearQuote("Amount must be greater than zero.");
    return;
  }

  const cowChainId = getCowChainId();
  const hasCowQuote = Boolean(getCowQuoteUrl(cowChainId));
  const elfomoQuoteContract = state.activeNetwork?.elfomoQuoteContract || "";
  const hasElfomoQuote = state.activeNetwork?.chainId === COW_CHAIN_ID_BASE && isAddress(elfomoQuoteContract);
  const contrapartyQuoteContract = normalizeAddress(state.activeNetwork?.contrapartyQuoteContract || "");
  const hasContrapartyQuote = Boolean(contrapartyQuoteContract);
  const kyberChainSlug = state.activeNetworkKey === "megaeth" ? getKyberChainSlug(state.activeNetwork?.chainId) : "";
  const hasKyberQuote = Boolean(kyberChainSlug);

  if (!hasCowQuote && !hasElfomoQuote && !hasContrapartyQuote && !hasKyberQuote) {
    clearQuote("Selected chain is not supported for quote backends.");
    return;
  }

  setStatus("Getting quote...");
  if (!state.swapBusy) setSwapButton("Getting Quote...", true);

  try {
    const provider = getProvider();
    const quoteOwner = await resolveQuoteOwner(recipientConfig);
    const quoteReceiver = recipientConfig.valid && recipientConfig.value ? recipientConfig.value : quoteOwner;

    const cowQuotePromise = hasCowQuote
      ? quoteCow(cowChainId, {
          sellToken: state.fromToken.address,
          buyToken: state.toToken.address,
          from: quoteOwner,
          receiver: quoteReceiver,
          kind: "sell",
          sellAmountBeforeFee: amountIn.toString()
        })
      : Promise.resolve(0n);

    const elfomoQuotePromise = hasElfomoQuote
      ? quoteElfomo(provider, elfomoQuoteContract, state.fromToken.address, state.toToken.address, amountIn)
      : Promise.resolve(0n);

    const contrapartyQuotePromise = hasContrapartyQuote
      ? quoteContraparty(provider, contrapartyQuoteContract, state.fromToken.address, state.toToken.address, amountIn)
      : Promise.resolve(0n);

    const kyberQuotePromise = hasKyberQuote
      ? quoteKyber(kyberChainSlug, state.fromToken.address, state.toToken.address, amountIn)
      : Promise.resolve(null);

    const [cowQuotedOut, elfomoQuotedOut, contrapartyQuotedOut, kyberQuoteResult] = await Promise.all([
      cowQuotePromise,
      elfomoQuotePromise,
      contrapartyQuotePromise,
      kyberQuotePromise
    ]);

    if (requestId !== state.quoteNonce) return;

    const candidates = [];
    if (cowQuotedOut > 0n) {
      candidates.push({
        source: "cow",
        label: "CoW Protocol",
        quotedOut: cowQuotedOut,
        spender: getCowVaultRelayerAddress(cowChainId),
        executable: true
      });
    }
    if (elfomoQuotedOut > 0n) {
      candidates.push({
        source: "elfomo",
        label: "ElfomoFi",
        quotedOut: elfomoQuotedOut,
        spender: normalizeAddress(elfomoQuoteContract),
        executable: true
      });
    }
    if (contrapartyQuotedOut > 0n) {
      candidates.push({
        source: "contraparty",
        label: "Contraparty",
        quotedOut: contrapartyQuotedOut,
        spender: contrapartyQuoteContract,
        executable: true
      });
    }
    if (kyberQuoteResult && kyberQuoteResult.quotedOut > 0n) {
      candidates.push({
        source: "kyber",
        label: "KyberSwap (Backup)",
        quotedOut: kyberQuoteResult.quotedOut,
        spender: kyberQuoteResult.routerAddress,
        kyberRouteSummary: kyberQuoteResult.routeSummary,
        kyberChainSlug,
        executable: true
      });
    }

    const pickBest = (entries) => {
      if (!entries || entries.length === 0) return null;
      return entries.reduce((best, candidate) => (candidate.quotedOut > best.quotedOut ? candidate : best));
    };

    const bestOverall = pickBest(candidates);
    const bestExecutable = pickBest(candidates.filter((candidate) => candidate.executable));

    let selected = bestExecutable || bestOverall;
    if (state.activeNetworkKey === "megaeth") {
      const megaethContraparty = candidates.find(
        (candidate) => candidate.source === "contraparty" && candidate.executable && candidate.quotedOut > 0n
      );
      if (megaethContraparty) {
        selected = megaethContraparty;
      } else {
        selected = bestExecutable || bestOverall;
      }
    }

    const quotedOut = selected?.quotedOut || 0n;
    const quoteSource = selected?.label || "No route available";
    const sourceKey = selected?.source || "";
    const spender = selected?.spender || "";
    const rawMinOut = quotedOut - (quotedOut * BigInt(slippageConfig.bps)) / 10_000n;
    const minOut = rawMinOut > 0n ? rawMinOut : 0n;

    els.toAmount.value = formatUnits(quotedOut, state.toToken.decimals);
    els.minOutInfo.textContent = `${formatUnits(minOut, state.toToken.decimals)} ${state.toToken.symbol} (${slippageConfig.label})`;

    if (quotedOut === 0n) {
      invalidateLatestQuote();
      els.routeInfo.textContent = "No route available";
      setQuoteHidden(false);
      setStatus("No quote returned for selected pair.");
      if (!state.swapBusy) void refreshSwapButtonState();
      return;
    }

    state.latestQuote = {
      source: sourceKey,
      sourceLabel: quoteSource,
      networkKey: state.activeNetworkKey,
      chainId: state.activeNetwork.chainId,
      cowChainId,
      fromToken: state.fromToken.address,
      toToken: state.toToken.address,
      amountIn,
      quotedOut,
      minOut,
      slippageBps: slippageConfig.bps,
      slippageLabel: slippageConfig.label,
      receiver: quoteReceiver,
      spender,
      executable: Boolean(selected && selected.executable),
      kyberRouteSummary: selected?.kyberRouteSummary || null,
      kyberChainSlug: selected?.kyberChainSlug || ""
    };

    els.routeInfo.textContent = `${quoteSource} (${state.activeNetwork.label})`;
    setQuoteHidden(false);
    const notices = [];
    if (slippageConfig.warning) notices.push(slippageConfig.warning);
    if (!recipientConfig.valid) notices.push("Recipient must be a valid address.");
    if (state.activeNetworkKey === "megaeth" && selected?.source === "kyber") {
      notices.push("Using KyberSwap backup route because Contraparty quote is unavailable.");
    }
    const suppressMegaethKyberHigherQuoteNotice =
      state.activeNetworkKey === "megaeth" && selected?.source === "contraparty" && bestOverall?.source === "kyber";

    if (bestOverall && selected && bestOverall.source !== selected.source && !suppressMegaethKyberHigherQuoteNotice) {
      if (bestOverall.executable) {
        notices.push(`Using ${selected.label} by preference; ${bestOverall.label} has a higher quoted amount.`);
      } else {
        notices.push(`Best quote from ${bestOverall.label} is not executable for current recipient.`);
      }
    }
    const updatedAt = formatClockTime();
    setStatus(notices.length > 0 ? notices.join(" ") : `Quote updated from ${quoteSource} at ${updatedAt}.`);
    if (!state.swapBusy) void refreshSwapButtonState();
  } catch (err) {
    if (requestId !== state.quoteNonce) return;
    clearQuote(`Quote failed: ${err.message || String(err)}`);
    if (!state.swapBusy) void refreshSwapButtonState();
  }
}

function scheduleQuote(delay = 220) {
  invalidateLatestQuote();
  if (!state.swapBusy) void refreshSwapButtonState();
  if (state.timer) {
    clearTimeout(state.timer);
    state.timer = null;
  }
  state.timer = setTimeout(() => {
    state.timer = null;
    void runQuote();
  }, delay);
}

function hasQuotableInputs() {
  const amountRaw = els.fromAmount.value.trim();
  if (!amountRaw) return false;
  if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) return false;

  try {
    const amountIn = parseUnits(amountRaw, state.fromToken.decimals);
    return amountIn > 0n;
  } catch {
    return false;
  }
}

function startQuoteAutoRefresh() {
  if (state.quoteRefreshTimer) clearInterval(state.quoteRefreshTimer);

  state.quoteRefreshTimer = setInterval(() => {
    void refreshFromTokenBalance();
    if (state.swapBusy || state.timer) return;
    if (!hasQuotableInputs()) return;
    void runQuote();
  }, QUOTE_REFRESH_MS);
}

async function approveTokenIfNeeded(walletClient, owner, quote) {
  const approvalState = await getApprovalState(owner, quote);
  if (!approvalState.needsApproval) return false;
  if (!approvalState.spender) {
    throw new Error("No spender configured for approval.");
  }

  setSwapBusy("Approving...");
  setStatus(`Sending approval to ${shortAddress(approvalState.spender)}...`);
  const txHash = await walletClient.writeContract({
    chain: walletClient.chain,
    account: owner,
    address: quote.fromToken,
    abi: ERC20_APPROVE_ABI,
    functionName: "approve",
    args: [approvalState.spender, MAX_UINT256]
  });
  const chainId = Number(walletClient.chain?.id || state.activeNetwork?.chainId || 0);
  setStatusTxLink("Approval submitted:", chainId, txHash);
  await getProvider().waitForTransactionReceipt({ hash: txHash });
  const cacheKey = approvalCacheKey(chainId, owner, quote.fromToken, approvalState.spender);
  if (cacheKey) {
    state.approvalCache.set(cacheKey, MAX_UINT256);
  }
  setStatusTxLink("Approval confirmed:", chainId, txHash);
  setSwapButton("Swap", false);
  return true;
}

async function executeContrapartySwap(walletClient, owner, quote, receiver) {
  const contrapartyAddress = normalizeAddress(state.activeNetwork?.contrapartyQuoteContract || quote.spender || "");
  if (!contrapartyAddress) {
    throw new Error("Contraparty contract is not configured on this chain.");
  }

  setSwapBusy("Swapping...");
  setStatus("Sending swap transaction to Contraparty...");
  const txHash = await walletClient.writeContract({
    chain: walletClient.chain,
    account: owner,
    address: contrapartyAddress,
    abi: CONTRAPARTY_SWAP_ABI,
    functionName: "swap",
    args: [quote.fromToken, quote.toToken, quote.amountIn, quote.minOut, receiver]
  });
  const chainId = Number(walletClient.chain?.id || state.activeNetwork?.chainId || 0);
  setStatusTxLink("Swap submitted:", chainId, txHash);
  await getProvider().waitForTransactionReceipt({ hash: txHash });
  setStatusTxLink("Swap confirmed via Contraparty:", chainId, txHash);
}

async function executeElfomoSwap(walletClient, owner, quote, receiver) {
  const elfomoAddress = normalizeAddress(state.activeNetwork?.elfomoQuoteContract || quote.spender || "");
  if (!elfomoAddress) {
    throw new Error("Elfomo contract is not configured on this chain.");
  }

  setSwapBusy("Swapping...");
  setStatus("Sending swap transaction to ElfomoFi...");
  const txHash = await walletClient.writeContract({
    chain: walletClient.chain,
    account: owner,
    address: elfomoAddress,
    abi: ELFOMO_SWAP_ABI,
    functionName: "swap",
    args: [quote.fromToken, quote.toToken, quote.amountIn, quote.minOut, receiver, 0n]
  });
  const chainId = Number(walletClient.chain?.id || state.activeNetwork?.chainId || 0);
  setStatusTxLink("Swap submitted:", chainId, txHash);
  await getProvider().waitForTransactionReceipt({ hash: txHash });
  setStatusTxLink("Swap confirmed via ElfomoFi:", chainId, txHash);
}

async function executeCowSwap(walletClient, owner, quote, receiver) {
  const cowChainId = Number(quote.cowChainId || getCowChainId());
  if (!cowChainId) {
    throw new Error("CoW Protocol is not configured for this chain.");
  }

  const { TradingSdk, ViemAdapter } = await loadCowSwapDeps();
  const adapter = new ViemAdapter({ provider: getProvider(), walletClient });

  setSwapBusy("Signing...");
  setStatus("Signing CoW order...");
  const tradingSdk = new TradingSdk(
    {
      chainId: cowChainId,
      appCode: APP_CODE
    },
    {},
    adapter
  );

  const result = await tradingSdk.postSwapOrder({
    chainId: cowChainId,
    appCode: APP_CODE,
    kind: "sell",
    owner,
    sellToken: quote.fromToken,
    sellTokenDecimals: state.fromToken.decimals,
    buyToken: quote.toToken,
    buyTokenDecimals: state.toToken.decimals,
    amount: quote.amountIn.toString(),
    receiver,
    slippageBps: quote.slippageBps
  });

  const orderId = typeof result === "string" ? result : result?.orderId;
  setStatus(`CoW order posted: ${orderId || "submitted"}.`);
}

async function buildKyberSwapTx(quote, owner, receiver) {
  const chainSlug = quote?.kyberChainSlug || getKyberChainSlug(state.activeNetwork?.chainId || 0);
  if (!chainSlug) {
    throw new Error("KyberSwap is not configured for this chain.");
  }
  if (!quote?.kyberRouteSummary) {
    throw new Error("Missing Kyber route summary.");
  }

  const buildRequest = async (enableGasEstimation) => {
    const response = await fetch(`${KYBER_API_BASE_URL}/${chainSlug}/api/v1/route/build`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-client-id": KYBER_CLIENT_ID
      },
      body: JSON.stringify({
        routeSummary: quote.kyberRouteSummary,
        sender: owner,
        recipient: receiver,
        slippageTolerance: Number(quote.slippageBps || 50),
        enableGasEstimation,
        source: KYBER_CLIENT_ID
      })
    });

    let payload = {};
    try {
      payload = await response.json();
    } catch {
      payload = {};
    }

    if (!response.ok || Number(payload?.code || 0) !== 0) {
      const message = payload?.message || `Kyber route build failed (${response.status}).`;
      throw new Error(message);
    }

    return payload;
  };

  let payload;
  try {
    payload = await buildRequest(true);
  } catch {
    payload = await buildRequest(false);
  }

  const data = payload?.data || {};
  const to = normalizeAddress(data.routerAddress || quote.spender || "");
  const callData = typeof data.data === "string" ? data.data : "";
  const value = parseBigIntLike(data.transactionValue || data.value);
  const gas = parseBigIntLike(data.gas);

  if (!to || !callData || !callData.startsWith("0x")) {
    throw new Error("Kyber route build returned invalid transaction data.");
  }

  return {
    to,
    data: callData,
    value,
    gas: gas > 0n ? gas : undefined
  };
}

async function executeKyberSwap(walletClient, owner, quote, receiver) {
  setSwapBusy("Building...");
  setStatus("Building KyberSwap transaction...");

  const tx = await buildKyberSwapTx(quote, owner, receiver);

  setSwapBusy("Swapping...");
  setStatus("Sending swap transaction to KyberSwap...");
  const txHash = await walletClient.sendTransaction({
    chain: walletClient.chain,
    account: owner,
    to: tx.to,
    data: tx.data,
    value: tx.value,
    gas: tx.gas
  });
  const chainId = Number(walletClient.chain?.id || state.activeNetwork?.chainId || 0);
  setStatusTxLink("Swap submitted:", chainId, txHash);
  await getProvider().waitForTransactionReceipt({ hash: txHash });
  setStatusTxLink("Swap confirmed via KyberSwap:", chainId, txHash);
}

async function handleSwapSubmit() {
  if (state.swapBusy) return;

  const recipientConfig = validateRecipient(state.recipient);
  if (!recipientConfig.valid) {
    setStatus("Recipient must be a valid address.");
    void refreshSwapButtonState();
    return;
  }

  let quote = state.latestQuote;
  if (!quote || isQuoteStale(quote) || quote.quotedOut <= 0n) {
    setStatus("Refreshing quote...");
    await runQuote();
    quote = state.latestQuote;
    if (!quote || isQuoteStale(quote) || quote.quotedOut <= 0n) {
      setStatus("Unable to swap without a valid quote.");
      void refreshSwapButtonState();
      return;
    }
  }

  if (quote.executable === false) {
    setStatus("Current route cannot execute with the selected recipient.");
    void refreshSwapButtonState();
    return;
  }

  let owner = await getWalletAccount(false);
  if (!owner) {
    owner = await getWalletAccount(true);
  }
  if (!owner) {
    setStatus("Connect wallet to continue.");
    void refreshSwapButtonState();
    return;
  }

  const walletChainId = await getWalletChainId();
  if (walletChainId !== state.activeNetwork.chainId) {
    try {
      setStatus(`Switching wallet to ${state.activeNetwork.label}...`);
      await ensureWalletChain(state.activeNetwork.chainId);
      setStatus(`Chain switched to ${state.activeNetwork.label}. Click Swap again.`);
      void refreshSwapButtonState();
      return;
    } catch (err) {
      if (isUserRejectedError(err)) {
        setStatus("User rejected the request.");
      } else {
        setStatus(`Chain switch failed: ${errorMessage(err, "Unable to switch chain.")}`);
      }
      void refreshSwapButtonState();
      return;
    }
  }

  const walletClient = getWalletClient(owner);
  owner = normalizeAddress(walletClient.account?.address || owner);
  const receiver = resolveExecutionRecipient(owner);

  if (isQuoteStale(quote)) {
    setStatus("Quote changed. Refreshing...");
    await runQuote();
    quote = state.latestQuote;
    if (!quote || isQuoteStale(quote) || quote.quotedOut <= 0n) {
      setStatus("Quote refresh failed. Try again.");
      void refreshSwapButtonState();
      return;
    }
  }

  if (quote.executable === false) {
    setStatus("Current route cannot execute with the selected recipient.");
    void refreshSwapButtonState();
    return;
  }

  try {
    const didApprove = await approveTokenIfNeeded(walletClient, owner, quote);
    if (didApprove) return;

    if (quote.source === "contraparty") {
      await executeContrapartySwap(walletClient, owner, quote, receiver);
      return;
    }

    if (quote.source === "elfomo") {
      await executeElfomoSwap(walletClient, owner, quote, receiver);
      return;
    }

    if (quote.source === "cow") {
      await executeCowSwap(walletClient, owner, quote, receiver);
      return;
    }

    if (quote.source === "kyber") {
      await executeKyberSwap(walletClient, owner, quote, receiver);
      return;
    }

    throw new Error("Unsupported route source.");
  } catch (err) {
    if (isUserRejectedError(err)) {
      setStatus("User rejected the request.");
    } else {
      setStatus(`Swap failed: ${errorMessage(err, "Unable to execute swap.")}`);
    }
  } finally {
    clearSwapBusy();
    void refreshFromTokenBalance();
    void refreshSwapButtonState();
  }
}

function renderTokenList(filter = "") {
  const needleRaw = filter.trim();
  const needle = needleRaw.toLowerCase();

  const matches = state.tokens.filter((token) => {
    if (!needle) return true;
    return token.address.toLowerCase().includes(needle);
  });

  let message = "";
  if (isAddressQuery(needleRaw)) {
    const normalized = normalizeAddress(needleRaw);
    if (normalized) {
      const lower = normalized.toLowerCase();
      if (!state.tokenByAddress.has(lower)) {
        if (state.dynamicTokenCache.has(lower)) {
          const dynamic = state.dynamicTokenCache.get(lower);
          if (dynamic) {
            matches.unshift(dynamic);
          } else {
            message = "Token metadata not found for that address.";
          }
        } else {
          message = "Looking up token metadata onchain...";
          void lookupTokenMetadata(normalized);
        }
      }
    }
  }

  if (matches.length === 0) {
    els.tokenList.innerHTML = `<p class="status">${message || "No tokens found."}</p>`;
    return;
  }

  els.tokenList.innerHTML = matches
    .map((token) => {
      const selected =
        (state.modalSide === "from" ? state.fromToken.address : state.toToken.address).toLowerCase() ===
        token.address.toLowerCase();

      return `
        <button class="token-item" data-address="${token.address}" ${selected ? "disabled" : ""}>
          <span class="token-item-left">
            <span>
              <span class="token-item-symbol">${token.symbol}</span><br/>
              <span class="token-item-address">${token.name || token.symbol} · ${shortAddress(token.address)}</span>
            </span>
          </span>
        </button>
      `;
    })
    .join("");

  els.tokenList.querySelectorAll(".token-item").forEach((button) => {
    button.addEventListener("click", () => {
      const selectedAddress = normalizeAddress(button.dataset.address);
      if (!selectedAddress) return;
      const lower = selectedAddress.toLowerCase();
      let selectedToken = state.tokenByAddress.get(lower);
      if (!selectedToken && state.dynamicTokenCache.has(lower)) {
        const dynamic = state.dynamicTokenCache.get(lower);
        if (dynamic) {
          selectedToken = upsertToken(dynamic);
        }
      }
      if (!selectedToken) return;

      if (state.modalSide === "from") {
        state.fromToken = selectedToken;
        if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) {
          const fallback = state.tokens.find((token) => token.address.toLowerCase() !== state.fromToken.address.toLowerCase());
          if (fallback) state.toToken = fallback;
        }
      } else {
        state.toToken = selectedToken;
        if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) {
          const fallback = state.tokens.find((token) => token.address.toLowerCase() !== state.toToken.address.toLowerCase());
          if (fallback) state.fromToken = fallback;
        }
      }

      renderTokenButtons();
      syncHashRoute();
      closeTokenModal();
      void refreshFromTokenBalance();
      scheduleQuote(0);
    });
  });
}

function openTokenModal(side) {
  state.modalSide = side;
  els.tokenSearch.value = "";
  renderTokenList("");
  els.tokenModal.hidden = false;
  requestAnimationFrame(() => els.tokenSearch.focus());
}

function closeTokenModal() {
  els.tokenModal.hidden = true;
}

function closeChainModal() {
  els.chainModal.hidden = true;
}

function pickNetworkToken(config, preferredSymbol, fallbackSymbol) {
  if (!config || !Array.isArray(config.tokens) || config.tokens.length === 0) return null;

  const preferred = String(preferredSymbol || "").toLowerCase();
  if (preferred) {
    const byPreferred = config.tokens.find((token) => token.symbol.toLowerCase() === preferred);
    if (byPreferred) return byPreferred;
  }

  const fallback = String(fallbackSymbol || "").toLowerCase();
  if (fallback) {
    const byFallback = config.tokens.find((token) => token.symbol.toLowerCase() === fallback);
    if (byFallback) return byFallback;
  }

  return config.tokens[0];
}

function switchNetwork(networkKey) {
  const nextConfig = APP_CONFIG.networks[networkKey];
  if (!nextConfig || !isNetworkSupported(nextConfig) || networkKey === state.activeNetworkKey) {
    closeChainModal();
    return;
  }

  const fromSymbol = state.fromToken?.symbol || nextConfig.defaultTokenIn;
  const toSymbol = state.toToken?.symbol || nextConfig.defaultTokenOut;

  const nextFromToken = pickNetworkToken(nextConfig, fromSymbol, nextConfig.defaultTokenIn);
  let nextToToken = pickNetworkToken(nextConfig, toSymbol, nextConfig.defaultTokenOut);

  if (!nextFromToken || !nextToToken) {
    closeChainModal();
    setStatus(`Unable to switch to ${nextConfig.label}.`);
    return;
  }

  if (nextFromToken.address.toLowerCase() === nextToToken.address.toLowerCase()) {
    const fallback = nextConfig.tokens.find((token) => token.address.toLowerCase() !== nextFromToken.address.toLowerCase());
    if (fallback) nextToToken = fallback;
  }

  state.activeNetworkKey = networkKey;
  state.activeNetwork = nextConfig;
  state.tokens = nextConfig.tokens;
  state.fromToken = nextFromToken;
  state.toToken = nextToToken;
  state.provider = null;
  state.providerKey = "";
  state.dynamicTokenCache = new Map();
  state.pendingTokenLookups = new Set();
  invalidateLatestQuote();

  buildTokenMaps(state.tokens);
  updateNetworkChip();
  renderTokenButtons();
  syncHashRoute();
  closeChainModal();
  setQuoteHidden(true);
  els.toAmount.value = "";
  els.routeInfo.textContent = "-";
  els.minOutInfo.textContent = "-";
  setStatus(`Switched to ${nextConfig.label}.`);

  void refreshFromTokenBalance();
  scheduleQuote(0);
}

function renderChainList() {
  const entries = Object.entries(APP_CONFIG.networks);
  els.chainList.innerHTML = entries
    .map(([key, cfg]) => {
      const selected = key === state.activeNetworkKey;
      const supported = isNetworkSupported(cfg);
      const label = supported ? cfg.label : `${cfg.label} (not supported)`;
      const disabled = selected || !supported;
      const classes = `token-item chain-item${supported ? "" : " chain-item-disabled"}`;
      return `<button class="${classes}" data-network="${key}" ${disabled ? "disabled" : ""}>${label}</button>`;
    })
    .join("");

  els.chainList.querySelectorAll(".chain-item").forEach((button) => {
    button.addEventListener("click", () => {
      const networkKey = button.dataset.network;
      if (!networkKey) return;
      switchNetwork(networkKey);
    });
  });
}

function openChainModal() {
  renderChainList();
  els.chainModal.hidden = false;
}

function flipTokens() {
  const current = state.fromToken;
  state.fromToken = state.toToken;
  state.toToken = current;

  renderTokenButtons();
  syncHashRoute();
  void refreshFromTokenBalance();
  scheduleQuote(0);
}

function wireEvents() {
  els.fromAmount.addEventListener("input", () => scheduleQuote());
  els.flipBtn.addEventListener("click", flipTokens);
  els.swapSubmitBtn.addEventListener("click", () => {
    void handleSwapSubmit();
  });

  els.fromTokenBtn.addEventListener("click", () => openTokenModal("from"));
  els.toTokenBtn.addEventListener("click", () => openTokenModal("to"));
  els.networkChip.addEventListener("click", openChainModal);
  els.advancedToggle.addEventListener("click", () => toggleAdvanced());

  els.slippageSelect.addEventListener("change", () => {
    state.slippageMode = els.slippageSelect.value;
    syncCustomSlippageInput();
    els.slippageCustom.classList.remove("invalid");
    scheduleQuote(0);
  });

  els.slippageCustom.addEventListener("input", () => {
    state.customSlippage = els.slippageCustom.value.trim();
    const customIsValid = parseCustomSlippageToBps(state.customSlippage) !== null;
    els.slippageCustom.classList.toggle("invalid", !customIsValid);
    scheduleQuote(0);
  });

  els.recipientInput.addEventListener("input", () => {
    state.recipient = els.recipientInput.value.trim();
    const recipient = validateRecipient(state.recipient);
    els.recipientInput.classList.toggle("invalid", !recipient.valid);
    scheduleQuote(0);
  });
  els.fromMaxBtn.addEventListener("click", () => fillFromAmountByBps(10_000));
  els.fromHalfBtn.addEventListener("click", () => fillFromAmountByBps(5_000));
  els.fromQuarterBtn.addEventListener("click", () => fillFromAmountByBps(2_500));

  els.closeModalBtn.addEventListener("click", closeTokenModal);
  els.tokenModal.addEventListener("click", (event) => {
    if (event.target === els.tokenModal) closeTokenModal();
  });
  els.closeChainModalBtn.addEventListener("click", closeChainModal);
  els.chainModal.addEventListener("click", (event) => {
    if (event.target === els.chainModal) closeChainModal();
  });

  els.tokenSearch.addEventListener("input", () => {
    renderTokenList(els.tokenSearch.value);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (!els.tokenModal.hidden) closeTokenModal();
    if (!els.chainModal.hidden) closeChainModal();
  });
}

function wireWalletEvents() {
  if (!window.ethereum || typeof window.ethereum.on !== "function" || window.__contrapartySwapBound) return;

  const handleWalletChange = () => {
    void refreshFromTokenBalance();
    void refreshSwapButtonState();
  };

  window.ethereum.on("accountsChanged", handleWalletChange);
  window.ethereum.on("chainChanged", handleWalletChange);
  window.ethereum.on("disconnect", handleWalletChange);
  window.__contrapartySwapBound = true;
}

function bootstrap() {
  renderAppVersion();

  state.activeNetworkKey = pickNetwork();
  state.activeNetwork = APP_CONFIG.networks[state.activeNetworkKey];
  if (!isNetworkSupported(state.activeNetwork)) {
    state.activeNetworkKey = firstSupportedNetworkKey();
    state.activeNetwork = APP_CONFIG.networks[state.activeNetworkKey];
  }
  state.tokens = state.activeNetwork.tokens;
  buildTokenMaps(state.tokens);

  const hashRoute = parseHashRoute();
  state.fromToken = tokenFromRef(hashRoute.tokenIn, state.activeNetwork.defaultTokenIn);
  state.toToken = tokenFromRef(hashRoute.tokenOut, state.activeNetwork.defaultTokenOut);

  if (state.fromToken.address.toLowerCase() === state.toToken.address.toLowerCase()) {
    const fallback = state.tokens.find((token) => token.address.toLowerCase() !== state.fromToken.address.toLowerCase());
    if (fallback) state.toToken = fallback;
  }

  els.slippageSelect.value = state.slippageMode;
  els.slippageCustom.value = state.customSlippage;
  els.recipientInput.value = state.recipient;
  syncCustomSlippageInput();
  toggleAdvanced(false);

  updateNetworkChip();
  renderTokenButtons();
  renderFromBalance(false);
  syncHashRoute();
  wireEvents();
  wireWalletEvents();
  startQuoteAutoRefresh();
  void refreshFromTokenBalance();
  clearQuote("Type an amount to get started.");
}

bootstrap();
