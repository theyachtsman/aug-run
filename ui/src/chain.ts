import {defineChain} from 'viem';
import {createConfig, http} from 'wagmi';
import {injected} from 'wagmi/connectors';

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: 'Robinhood Chain Testnet',
  nativeCurrency: {name: 'Ether', symbol: 'ETH', decimals: 18},
  rpcUrls: {
    default: {http: ['https://rpc.testnet.chain.robinhood.com']},
  },
  blockExplorers: {
    default: {
      name: 'Robinhood Explorer',
      url: 'https://explorer.testnet.chain.robinhood.com',
    },
  },
  contracts: {
    // Verified deployed on this chain — lets wagmi batch reads into one call, which
    // matters when scanning up to 333 ownerOf() lookups to find your units.
    multicall3: {address: '0xcA11bde05977b3631167028862bE2a173976CA11'},
  },
});

export const config = createConfig({
  chains: [robinhoodTestnet],
  connectors: [injected()],
  transports: {
    [robinhoodTestnet.id]: http(),
  },
});

declare module 'wagmi' {
  interface Register {
    config: typeof config;
  }
}
