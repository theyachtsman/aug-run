# AUG//RUN — mainnet launch runbook

For launching **$RUN** on Robinhood Chain mainnet (chain `4663`) via the StonkBrokers Stonk Launcher.

> **This deploy cannot be undone.** Supply is fixed at 1,000,000,000, minted once in the constructor.
> There is no owner, no mint function, no upgrade path, and no admin key. The `TREASURY` address you
> pass holds the entire supply permanently.

---

## Before you touch a key

### 1. Decide the treasury — this is the decision that matters

Whatever address you pass receives 1,000,000,000 $RUN forever. A **multisig** is the right home for
a whole token supply; an EOA means a single compromised key is the whole project.

The preflight warns on an EOA and hard-fails if it is the testnet throwaway.

### 2. Use a fresh deployer key

`~/.aug_run/.env` currently holds a **testnet throwaway** (`0x5a56B2f1…`). It has signed dozens of
testnet transactions and lives in a plaintext file on a drive where `chmod` does not persist. It must
not be the mainnet deployer or treasury. Generate a new key — ideally a hardware wallet — and keep it
off this drive.

### 3. Know what is NOT ready

Launching $RUN starts a clock. From the spec (`aug_run_spec.md:399`):

> launching $RUN sets a clock. Once it trades, holders expect the mint, so the site and art should be
> finished before the token launches rather than after.

At time of writing, the mint **cannot open**:

| | Status |
|---|---|
| `$RUN` token | ready for mainnet ✅ |
| `StockRunner` (the mint) | **testnet only** — needs a freeze review first |
| Ripperdoc / Black Market / Terminal / Fixer / Chop Shop / Drop | testnet only |
| 4 testnet stubs | must be replaced (see below) |

`StockRunner` is the one contract that must be final before *any* unit exists, because the ERC-6551
wallet address derives from the token contract's address — redeploying it strands every unit's
wallet and its contents.

---

## The deploy

```bash
# 1. Put the mainnet key + addresses somewhere safe (NOT in the repo)
cp .env.example ~/.aug_run/mainnet.env
chmod 600 ~/.aug_run/mainnet.env
$EDITOR ~/.aug_run/mainnet.env
```

```ini
PRIVATE_KEY=0x<FRESH KEY, never used on testnet>
AUGRUN_TESTNET=false          # MUST be false — disables faucets, allocates no faucet pot
TREASURY=0x<multisig>         # holds 1,000,000,000 $RUN forever

# $AUG is deployed by the same script. Set these deliberately or it defaults to the deployer.
AUG_CIRCULATING=0x<...>       # 80,000,000
PROTOCOL_RESERVE=0x<...>      # 15,000,000
LAUNCH_SEED=0x<...>           #  5,000,000
```

```bash
# 2. Preflight — simulates only, never broadcasts. Refuses on any of:
#    testnet flag set, testnet key, unset treasury, wrong chain, no gas.
AUGRUN_ENV_FILE=~/.aug_run/mainnet.env NETWORK=rh_mainnet bin/preflight-mainnet.sh

# 3. Only if preflight is clean:
AUGRUN_ENV_FILE=~/.aug_run/mainnet.env NETWORK=rh_mainnet bin/deploy.sh phase1
```

### Verify immediately after

```bash
cast call $RUN 'totalSupply()(uint256)'   --rpc-url rh_mainnet   # 1e27
cast call $RUN 'TESTNET()(bool)'          --rpc-url rh_mainnet   # false
cast call $RUN 'faucetRemaining()(uint256)' --rpc-url rh_mainnet # 0
cast call $RUN 'balanceOf(address)(uint256)' $TREASURY --rpc-url rh_mainnet  # 1e27
cast call $RUN 'owner()'                  --rpc-url rh_mainnet   # must REVERT (no owner)
```

Rehearsed on a local chain-4663 stand-in: mainnet mode yields 1e27 supply to treasury, `TESTNET`
false, zero faucet pot, `faucet()` reverting, and no `owner()` or `mint()` functions at all.

---

## Known issue: the Terminal cannot stake Uniswap V3 liquidity

StonkBrokers launches into a **Uniswap V3** pool against WETH. A V3 position is an **ERC-721 NFT**,
not a fungible ERC-20 LP token. `Terminal.stake(true, …)` takes an ERC-20, so a V3 position cannot be
staked and the 20% LP bucket would accrue with no valid claimant.

Not urgent for a $RUN launch — the Terminal rewards **$AUG** liquidity, and there is no $AUG pool or
protocol revenue yet. But it must be solved before the Terminal goes to mainnet. Options:

1. A V3 position staker that accepts the NFT and weights by liquidity in the canonical pool. Correct,
   and real work — it has to handle price ranges and in/out-of-range liquidity.
2. An ERC-20 wrapper around V3 positions.
3. Redirect the LP 20% until a staker exists.

---

## The four testnet stubs that must not ship

| Stub | Why it cannot ship | Replace with |
|---|---|---|
| `TestnetRunPriceOracle` | owner can set any price; sell fees and Fixer LTV read it | real $RUN/ETH TWAP or feed |
| `CommitRevealRandomness` | sequencer could influence the target block hash | Chainlink VRF — **not supported on Robinhood Chain today** |
| `MockRwaVenue` | mints assets from nothing | real Stock Token liquidity + Chainlink Data Feeds (live on RH Chain) |
| `MockUSDG` / `MockLpToken` | represent nothing, mint freely | real USDG; real LP position handling |

All four sit behind interfaces (`IRunPriceOracle`, `IRandomnessSource`, `IRwaVenue`,
`Terminal.setLpToken`), so each swaps in without redeploying its consumer.
