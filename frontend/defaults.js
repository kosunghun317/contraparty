const BASE_TOKENS = [
  { symbol: "WETH", address: "0x4200000000000000000000000000000000000006", decimals: 18 },
  { symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6 },
  { symbol: "cbBTC", address: "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf", decimals: 8 }
];

const ETHEREUM_TOKENS = [
  { symbol: "WETH", address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", decimals: 18 },
  { symbol: "USDC", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6 }
];

const MEGAETH_TOKENS = [
  { symbol: "WETH", address: "0x4200000000000000000000000000000000000006", decimals: 18 },
  { symbol: "USDm", address: "0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7", decimals: 18 },
  { symbol: "USDT0", address: "0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb", decimals: 6 },
  { symbol: "BTC.b", address: "0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072", decimals: 8 }
];

export const APP_VERSION = "2026.02.22.2";

export const APP_CONFIG = {
  defaultNetwork: "megaeth",
  networks: {
    ethereum: {
      label: "Ethereum",
      chainId: 1,
      cowChainId: 1,
      supported: true,
      elfomoQuoteContract: "",
      contrapartyQuoteContract: "",
      contrapartyVersion: "v1",
      rpcUrl: "https://ethereum-rpc.publicnode.com",
      rpcUrls: [
        "https://ethereum-rpc.publicnode.com",
        "https://eth.llamarpc.com",
        "https://rpc.ankr.com/eth"
      ],
      routers: {
        a: "",
        b: ""
      },
      iterations: 12,
      tokens: ETHEREUM_TOKENS,
      defaultTokenIn: "WETH",
      defaultTokenOut: "USDC"
    },
    base: {
      label: "Base",
      chainId: 8453,
      cowChainId: 8453,
      supported: true,
      elfomoQuoteContract: "0xf0f0F0F0FB0d738452EfD03A28e8be14C76d5f73",
      contrapartyQuoteContract: "0x0341F4282D10C1A130C21CE0BDcE82076951e819",
      contrapartyVersion: "v1",
      rpcUrl: "https://base-rpc.publicnode.com",
      rpcUrls: [
        "https://base-rpc.publicnode.com",
        "https://base.drpc.org",
        "https://base.llamarpc.com"
      ],
      routers: {
        a: "",
        b: ""
      },
      iterations: 12,
      tokens: BASE_TOKENS,
      defaultTokenIn: "WETH",
      defaultTokenOut: "USDC"
    },
    megaeth: {
      label: "MegaETH",
      chainId: 4326,
      cowChainId: 0,
      supported: true,
      elfomoQuoteContract: "",
      contrapartyQuoteContract: "0x2Ede240d8E64e7Be3B103d9434733D56caFd9059",
      contrapartyVersion: "v2",
      rpcUrl: "https://mainnet.megaeth.com/rpc",
      rpcUrls: [
        "https://mainnet.megaeth.com/rpc"
      ],
      routers: {
        a: "",
        b: ""
      },
      iterations: 12,
      tokens: MEGAETH_TOKENS,
      defaultTokenIn: "WETH",
      defaultTokenOut: "USDm"
    }
  }
};
