// Robinhood Chain testnet (46630) deployment. Mirrors DEPLOYMENTS.md.
// Override any of these at dev time with a VITE_<NAME>_ADDRESS env var.

const env = import.meta.env;

export const addresses = {
  RUN: (env.VITE_RUN_ADDRESS ?? '0x511Ec1101FABF810fb82bDA0BF03e439f3324c69') as `0x${string}`,
  AUG: (env.VITE_AUG_ADDRESS ?? '0xc8E656aCfDA836f3ec89c97e9B4aA6BB72237734') as `0x${string}`,
  StockRunner: (env.VITE_STOCKRUNNER_ADDRESS ??
    '0x7d17e34DFdA1951843B3A7E2e7f5074Fb8d0307B') as `0x${string}`,
  Augments: (env.VITE_AUGMENTS_ADDRESS ??
    '0xE22CDA4317CfAFfBe7Ca3720B043dd4463188179') as `0x${string}`,
  ExpansionModules: (env.VITE_MODULES_ADDRESS ??
    '0xd9052fA1f5709a847B975A07e85CCB68e8d86e6D') as `0x${string}`,
  Ripperdoc: (env.VITE_RIPPERDOC_ADDRESS ??
    '0xe267f687d5E774bd82AcaFbD7A4c4A479BC94876') as `0x${string}`,
  BlackMarket: (env.VITE_BLACKMARKET_ADDRESS ??
    '0x5150d570EA1979E3eaE611F2c215eB097eA2e9fe') as `0x${string}`,
  RevenueSplitter: (env.VITE_SPLITTER_ADDRESS ??
    '0x3ac75FB57B5D62fDd0C8A9188Eaef676914c2c52') as `0x${string}`,
  Terminal: (env.VITE_TERMINAL_ADDRESS ??
    '0x6258CBB504150fDAEDBd751e81C8aa873Ee46b54') as `0x${string}`,
  MockLpToken: (env.VITE_MOCKLP_ADDRESS ??
    '0x5715047379A0DDEF0De71cd78C301F4c72085F91') as `0x${string}`,
  Fixer: (env.VITE_FIXER_ADDRESS ??
    '0xCF4F286Fbf5b08f85cb98bCE61f4d14b284e50Dc') as `0x${string}`,
  ProtocolReserve: (env.VITE_RESERVE_ADDRESS ??
    '0x46b711D6E60f3B8c5e6439Bc5fa2cf757f8Dc99a') as `0x${string}`,
  ChopShop: (env.VITE_CHOPSHOP_ADDRESS ??
    '0xb5a0B37E47a895526b7786f90CDBA527aB3a454f') as `0x${string}`,
  Randomness: (env.VITE_RANDOMNESS_ADDRESS ??
    '0xA545C149337976C3681dE401c23952A75185F2f0') as `0x${string}`,
  USDG: (env.VITE_USDG_ADDRESS ??
    '0x1E10e5e217D3872c4Aea49C28c08ca2FED972341') as `0x${string}`,
  Drop: (env.VITE_DROP_ADDRESS ??
    '0x2a516713F3c7EfD280Ed83753CD5B3336e83735f') as `0x${string}`,
  RwaVenue: (env.VITE_RWAVENUE_ADDRESS ??
    '0x119e2a554261920D2Deb470eaC6ADD25fA4831be') as `0x${string}`,
  PriceOracle: (env.VITE_ORACLE_ADDRESS ??
    '0x8bbFb7fdAae6A284C25E7cC970f3245eb07bC65B') as `0x${string}`,
} as const;

export const EXPLORER = 'https://explorer.testnet.chain.robinhood.com';
