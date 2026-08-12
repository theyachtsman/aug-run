import {defineChain} from 'viem';
import {createConfig, http, cookieStorage, createStorage} from 'wagmi';
import {injected} from 'wagmi/connectors';

/** Robinhood Chain mainnet. Verified live: Nitro v3.11.3, ERC-6551 registry and Multicall3 present. */
export const robinhood = defineChain({
  id: 4663,
  name: 'Robinhood Chain',
  nativeCurrency: {name: 'Ether', symbol: 'ETH', decimals: 18},
  rpcUrls: {default: {http: ['https://rpc.mainnet.chain.robinhood.com']}},
  blockExplorers: {default: {name: 'Explorer', url: 'https://explorer.chain.robinhood.com'}},
  contracts: {multicall3: {address: '0xcA11bde05977b3631167028862bE2a173976CA11'}},
});

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: 'Robinhood Chain Testnet',
  nativeCurrency: {name: 'Ether', symbol: 'ETH', decimals: 18},
  rpcUrls: {default: {http: ['https://rpc.testnet.chain.robinhood.com']}},
  blockExplorers: {
    default: {name: 'Explorer', url: 'https://explorer.testnet.chain.robinhood.com'},
  },
  contracts: {multicall3: {address: '0xcA11bde05977b3631167028862bE2a173976CA11'}},
});

/**
 * Which chain the site talks to. Testnet until the mainnet contracts exist — flip with
 * NEXT_PUBLIC_CHAIN=mainnet once they do.
 */
export const ACTIVE_CHAIN =
  process.env.NEXT_PUBLIC_CHAIN === 'mainnet' ? robinhood : robinhoodTestnet;

/**
 * Both chains are registered so a wallet sitting on either is recognised rather than treated as
 * unknown — the HUD compares against ACTIVE_CHAIN and prompts a switch. It also makes the
 * testnet → mainnet cutover a one-line env change instead of a config rewrite.
 */
export const config = createConfig({
  chains: [robinhood, robinhoodTestnet],
  connectors: [injected()],
  // SSR-safe: wagmi must not touch localStorage while rendering on the server.
  ssr: true,
  storage: createStorage({storage: cookieStorage}),
  transports: {
    [robinhood.id]: http(),
    [robinhoodTestnet.id]: http(),
  },
});

export const EXPLORER = ACTIVE_CHAIN.blockExplorers!.default.url;

declare module 'wagmi' {
  interface Register {
    config: typeof config;
  }
}
