import {ACTIVE_CHAIN} from './chain';

type Deployment = {
  RUN: `0x${string}`;
  AUG: `0x${string}`;
  StockRunner: `0x${string}`;
  Augments: `0x${string}`;
  ExpansionModules: `0x${string}`;
  Ripperdoc: `0x${string}`;
  BlackMarket: `0x${string}`;
  RevenueSplitter: `0x${string}`;
  Terminal: `0x${string}`;
  Fixer: `0x${string}`;
  ProtocolReserve: `0x${string}`;
  ChopShop: `0x${string}`;
  Drop: `0x${string}`;
  PriceOracle: `0x${string}`;
  Randomness: `0x${string}`;
  RwaVenue: `0x${string}`;
  USDG: `0x${string}`;
  MockLpToken: `0x${string}`;
};

const ZERO = '0x0000000000000000000000000000000000000000' as const;

/** Testnet (46630) — the live deployment the site develops against. */
const testnet: Deployment = {
  RUN: '0x511Ec1101FABF810fb82bDA0BF03e439f3324c69',
  AUG: '0xc8E656aCfDA836f3ec89c97e9B4aA6BB72237734',
  StockRunner: '0x7d17e34DFdA1951843B3A7E2e7f5074Fb8d0307B',
  Augments: '0xE22CDA4317CfAFfBe7Ca3720B043dd4463188179',
  ExpansionModules: '0xd9052fA1f5709a847B975A07e85CCB68e8d86e6D',
  Ripperdoc: '0xe267f687d5E774bd82AcaFbD7A4c4A479BC94876',
  BlackMarket: '0x5150d570EA1979E3eaE611F2c215eB097eA2e9fe',
  RevenueSplitter: '0x3ac75FB57B5D62fDd0C8A9188Eaef676914c2c52',
  Terminal: '0x6258CBB504150fDAEDBd751e81C8aa873Ee46b54',
  Fixer: '0xCF4F286Fbf5b08f85cb98bCE61f4d14b284e50Dc',
  ProtocolReserve: '0x46b711D6E60f3B8c5e6439Bc5fa2cf757f8Dc99a',
  ChopShop: '0xb5a0B37E47a895526b7786f90CDBA527aB3a454f',
  Drop: '0x2a516713F3c7EfD280Ed83753CD5B3336e83735f',
  PriceOracle: '0x8bbFb7fdAae6A284C25E7cC970f3245eb07bC65B',
  Randomness: '0xA545C149337976C3681dE401c23952A75185F2f0',
  RwaVenue: '0x119e2a554261920D2Deb470eaC6ADD25fA4831be',
  USDG: '0x1E10e5e217D3872c4Aea49C28c08ca2FED972341',
  MockLpToken: '0x5715047379A0DDEF0De71cd78C301F4c72085F91',
};

/** Mainnet (4663) — nothing deployed yet. Fill in as each lands. */
const mainnet: Deployment = {
  RUN: ZERO,
  AUG: ZERO,
  StockRunner: ZERO,
  Augments: ZERO,
  ExpansionModules: ZERO,
  Ripperdoc: ZERO,
  BlackMarket: ZERO,
  RevenueSplitter: ZERO,
  Terminal: ZERO,
  Fixer: ZERO,
  ProtocolReserve: ZERO,
  ChopShop: ZERO,
  Drop: ZERO,
  PriceOracle: ZERO,
  Randomness: ZERO,
  RwaVenue: ZERO,
  USDG: ZERO,
  MockLpToken: ZERO,
};

export const addresses: Deployment = ACTIVE_CHAIN.id === 4663 ? mainnet : testnet;

/** True when the active chain has no deployment yet — the UI degrades rather than erroring. */
export const isDeployed = addresses.StockRunner !== ZERO;
