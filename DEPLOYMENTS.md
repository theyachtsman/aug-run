# AUG//RUN — Deployments

Contract addresses per phase. Contracts live on **Robinhood Chain testnet**; the test UI is served
from localhost (port 3333, bound to all interfaces).

## Networks

| | Testnet | Mainnet |
|---|---|---|
| Chain ID | `46630` | `4663` |
| RPC | `https://rpc.testnet.chain.robinhood.com` | `https://rpc.chain.robinhood.com` |
| Explorer | `https://explorer.testnet.chain.robinhood.com` | — |
| Faucet | `https://faucet.testnet.chain.robinhood.com` | — |

Verified live on testnet: Nitro `v3.11.3`, ArbOS `116`, gas price `0.01 gwei`.

## Current deployment (2026-08-11, phases 1–8 — COMPLETE)

Adding ERC-2981 to the ERC-721 required a fresh `StockRunner` — royalties cannot be bolted on after
deploy — which cascaded into `Augments`, `ExpansionModules` and `Ripperdoc`. `RUN`, `AUG` and the
ERC-6551 account implementation were **reused**.

| Contract | Address | Status |
|---|---|---|
| `RUN` | `0x511Ec1101FABF810fb82bDA0BF03e439f3324c69` | reused |
| `AUG` | `0xc8E656aCfDA836f3ec89c97e9B4aA6BB72237734` | reused |
| `StockRunner` | `0x7d17e34DFdA1951843B3A7E2e7f5074Fb8d0307B` | **new** — now ERC-2981 |
| `Ripperdoc` | `0xe267f687d5E774bd82AcaFbD7A4c4A479BC94876` | **new** |
| `Augments` | `0xE22CDA4317CfAFfBe7Ca3720B043dd4463188179` | **new** |
| `ExpansionModules` | `0xd9052fA1f5709a847B975A07e85CCB68e8d86e6D` | **new** |
| `BlackMarket` | `0x5150d570EA1979E3eaE611F2c215eB097eA2e9fe` | **new** (phase 6 — v2, can lend) |
| `RevenueSplitter` | `0x3ac75FB57B5D62fDd0C8A9188Eaef676914c2c52` | **new** (phase 4) |
| `TestnetRunPriceOracle` | `0x8bbFb7fdAae6A284C25E7cC970f3245eb07bC65B` | **new** (phase 4) |
| `Terminal` | `0x6258CBB504150fDAEDBd751e81C8aa873Ee46b54` | **new** (phase 5) |
| `MockLpToken` | `0x5715047379A0DDEF0De71cd78C301F4c72085F91` | **new** (phase 5, testnet only) |
| `Fixer` | `0xCF4F286Fbf5b08f85cb98bCE61f4d14b284e50Dc` | **new** (phase 6) |
| `ProtocolReserve` | `0x46b711D6E60f3B8c5e6439Bc5fa2cf757f8Dc99a` | **new** (phase 6) |
| `ChopShop` | `0xb5a0B37E47a895526b7786f90CDBA527aB3a454f` | **new** (phase 7) |
| `CommitRevealRandomness` | `0xA545C149337976C3681dE401c23952A75185F2f0` | **new** (phase 7) |
| `MockUSDG` | `0x1E10e5e217D3872c4Aea49C28c08ca2FED972341` | **new** (phase 7, testnet only) |
| `Drop` | `0x2a516713F3c7EfD280Ed83753CD5B3336e83735f` | **new** (phase 8) |
| `MockRwaVenue` | `0x119e2a554261920D2Deb470eaC6ADD25fA4831be` | **new** (phase 8, testnet only) |
| `ERC6551Account` (impl) | `0x8A7406854Fc2a34B306f308AD949aEd484Df55f0` | reused |
| ERC-6551 Registry | `0x000000006551c19487814612e58FE06813775758` | pre-existing, pointed at |

Deployer / protocol reserve: `0x5a56B2f1E1e7ecf34F74039B656D88361E208957`.

Wiring confirmed on-chain: `StockRunner.ripperdoc` → Ripperdoc, `StockRunner.treasury` →
BlackMarket, royalty receiver → RevenueSplitter, `Augments.ripperdoc` and
`ExpansionModules.ripperdoc` → Ripperdoc.

### Superseded (do not use)

`CHROME` `0xfC121e3a…7ce1` · `StockRunner` `0x382492cd…D353`, `0x1c4C6aCF…7252` ·
`Ripperdoc` `0x03167280…60f3`, `0xa5F02C1f…AC31` · `Augments` `0xF08a9F5D…A1b6`, `0x906200F9…7FEa` ·
`ExpansionModules` `0x9748d8Ee…Eb17`, `0xa0BBAFf0…28aa` · `BlackMarket` `0xABc4CE54…6b23` (holds 3,000,000 stranded $RUN — no withdraw function by design).

## Pre-existing infrastructure (do not deploy)

The canonical ERC-6551 registry is **already live** on RH testnet. Confirmed by fetching its runtime
bytecode and matching the dispatcher against the canonical selectors `0x246a0021`
(`account(address,bytes32,uint256,address,uint256)`) and `0x8a54c52f` (`createAccount(...)`).

Tokenbound's account implementation (`0x41C8f394…44eC`) is **not** on this chain, so we deploy the
EIP-6551 reference account implementation. Per spec, no custom TBA is written.

Multicall3 is also live at `0xcA11bde05977b3631167028862bE2a173976CA11` — declared in the UI's chain
config so the up-to-333 `ownerOf` ownership scan batches into one call.

## Phase 1 — Tokens

`RUN`: 1,000,000,000 fixed supply, 18 dp, no burn, no mint after construction, no owner.
`AUG`: 100,000,000 initial supply, 18 dp, burnable one-way. Launch split 80% circulating /
15% protocol reserve / 5% launch seed — verified exact.

Faucet drip per claim: **5,000,000 $RUN** (five genesis mints) and **10,000 $AUG** (twenty tier-3
Augments), 1 hour per-address cooldown each. Both gated behind an immutable `TESTNET` flag; the
faucet never mints, it transfers from a pot carved out at construction.

## Phase 2 — Stock//Runner core

`MAX_SUPPLY` 333 · `GENESIS_PRICE` 1e24 ($RUN) · `MODEL_COUNT` 11 · `MAX_BAYS` 3.

Model draw is an exact-count bucket walk seeded at deploy and bound to `msg.sender`, so the final
distribution is exactly **31/31/31 + 30×8** and a caller cannot reroll. Verified by a full 333-unit
mint-out in tests.

Clock: `CYCLE_GENESIS` = `1767571200` = **Monday 2026-01-05 00:00:00 UTC**, one week per cycle.
Observed ticking from cycle 30 to **31** across the real Monday 2026-08-10 boundary between deploys.

## Phase 3 — Augments, Expansion Modules, Ripperdoc

### Launch catalog — 12 Augments, 4 per tier

Tickers are **placeholders**. The real twelve depend on what is genuinely tokenized and liquid as
Stock Tokens on Robinhood Chain at launch. `addAugment(ticker, tier)` appends more at any time
without redeploying anything or touching weight math.

| Tier | Price | Weight | IDs |
|---|---|---|---|
| 1 | 100 $AUG | 1.0x | 1 SPY · 2 JNJ · 3 BRKB · 4 TSLA |
| 2 | 250 $AUG | 1.25x | 5 QQQ · 6 AAPL · 7 KO · 8 COIN |
| 3 | 500 $AUG | 1.5x | 9 NVDA · 10 MSFT · 11 AMD · 12 GLD |

### Live walkthrough on the new deployment (unit #1, bay 0, NVDA)

| Check | Value | Meaning |
|---|---|---|
| `modelOf(1)` | 7 | drawn from the bucket |
| `TBA(1)` | `0x3A6223AA5301eBd3E6e6842ec62f41268Ab8306d` | matched the pre-mint prediction |
| `AUG.totalSupply()` delta | −250e18 | exactly half of the 500 paid, burned |
| `getBay(1,0)` | `(9, 3, 31, 31, true)` | NVDA, tier 3, seated cycle 31, locked cycle 31 |
| `bayWeight(1,0)` | 1.5e18 | fresh tier-3 |
| `unitEligibleWeight(1)` | **0** | seasoning: seated mid-cycle earns nothing this cycle |

## Wiring policy

`setRipperdoc` on `StockRunner`, `Augments` and `ExpansionModules` is **strictly set-once when
`TESTNET` is false**, and re-pointable by the owner when it is true. That address can rewrite every
unit's seating and tenure and can mint items freely, so it must not be re-pointable in production —
but under strict set-once every later phase that replaces the Ripperdoc would force a fresh
StockRunner and a re-mint of every test unit. Same gating pattern as the faucets and
`advanceCycles`. Covered by tests on both branches.

## Phase 4 — The Black Market, royalties, the 60/20/20

### Model

The Black Market is the **floor and instant-liquidity venue**, not where a built unit gets its
premium. Operators sell units into a pool; buyers take a random one (10% fee) or name a specific one
(15%). One quote covers every unit the pool holds, so it cannot pay more for a tenured Runner — and
is not meant to. Premium units trade on external venues, which is exactly what the 5% ERC-2981
royalty exists to capture.

The curve is linear on the pool's own spot price: each purchase steps it up by `delta`, each sale
steps it down, floored at `minSpotPrice`. Simple enough to predict the next quote without modelling
anything — the same reasoning as the linear tenure curve.

| Parameter | Value |
|---|---|
| initial spot | 1,000,000 $RUN (opens at the genesis price) |
| delta | 25,000 $RUN per trade |
| floor | 100,000 $RUN |
| buy fee | 10% random · 15% specific |
| sell fee | 25% under 0.1 ETH · 15% from 0.1 to 1 ETH · 10% above 1 ETH |
| royalty | 5% ERC-2981, below every Black Market fee tier by design |

Genesis activation routes through `BlackMarket.activateGenesis()`. The 1,000,000 $RUN round-trips
through the StockRunner and lands back in the pool (treasury = BlackMarket), which is what gives the
pool the liquidity to buy units back — and what the Fixer will lend against in phase 6.

### The price oracle

Robinhood Chain testnet has **no DEX, no WETH and no price feed** (verified by probing the canonical
Uniswap V2/V3 factory and WETH addresses — none deployed; only Permit2 exists). The sell fee tiers
are ETH-denominated, so `IRunPriceOracle` is an interface with a swappable implementation.
`TestnetRunPriceOracle` is owner-settable — fine for a harness, unacceptable in production. Mainnet
points `setPriceOracle` at a real pool TWAP or feed; the Black Market needs no change.

### Live walkthrough

Two genesis activations, then a full round trip on unit #1:

| Step | Observed |
|---|---|
| 2 × `activateGenesis` | `poolLiquidity` 2,000,000 $RUN · `poolSize` 0 (activated units aren't pool stock) |
| `sell(1)` | price 975,000 · fee 146,250 (15%, unit at 0.975 ETH) · payout **828,750** |
| after sale | spot stepped **down** to 975,000 · `poolSize` 1 · pool owns #1 |
| `buySpecific(1)` | price 975,000 + 146,250 fee = **1,121,250** total |
| after purchase | spot stepped **up** to 1,000,000 · `poolSize` 0 |
| fees | `lifetimeFees` 292,500 → splitter **175,500 / 58,500 / 58,500** = exactly 60/20/20 |
| `royaltyInfo(1, 1 ETH)` | RevenueSplitter, 0.05 ETH |
| `supportsInterface` | ERC-2981 ✅ · ERC-721 ✅ |

The round trip cost more than it returned — buy/sell spread plus fees — which is what stops the pool
being drained by cycling a unit through it.

### Splitter recipients

Deliberately unwired: the Terminal (phase 5) and the Drop (phase 8) don't exist yet. Fees accrue in
`RevenueSplitter` and stay claimable once those land. External royalties arrive as raw transfers
(marketplaces never call a function), so `sync(asset)` sweeps them into the same split — anyone may
call it.

## Phase 5 — The Terminal

Two staking pools in one unstaffed contract. Stake **$AUG** to earn the Stakers bucket (20% of every
fee); stake an **LP token** to earn the LPs bucket (20%). This is what finally makes 40% of protocol
revenue claimable — the Drop's 60% keeps accruing untouched until phase 8.

| | |
|---|---|
| reward asset | $RUN (every Black Market fee is denominated in it) |
| reward duration | 7 days, matching the cycle |
| lock / unbonding | **none** — stake, unstake and claim at any time |
| `pullRewards()` | permissionless |

### Why rewards stream instead of landing in a lump

Revenue reaches the splitter continuously but is *claimed* in discrete chunks. Paying a chunk out
instantly would let someone stake immediately before the claim, take a share of the whole amount and
unstake straight after. Streaming makes that worthless — you earn only for the seconds you were
actually staked. `test_jitStakerCapturesAlmostNothing` pins it: the sniper collects exactly **0**.

Streaming controls the accrual *rate*, never access to funds. Staking, unstaking and claiming remain
available at every moment.

### Revenue arriving with nobody staked

Streaming into an empty pool would make the revenue irrecoverable, so it is **queued** instead and
begins streaming on the first stake. Covered by tests.

### Live walkthrough

Staked 10,000 $AUG and 1,000 mock LP, then `pullRewards()` claimed the 58,500 $RUN sitting in each
of the two buckets:

| Check | Value |
|---|---|
| `rewardRate` | 96,726,190,476,190,476 wei/s = 58,500 ÷ 604,800 ✅ |
| accrued over a 40s wait | 3.97 $RUN (≈ 0.0967 × 40) ✅ |
| claim mid-stream | paid out, stake untouched ✅ |
| unstake immediately after | succeeded — no lock ✅ |
| splitter Drop bucket | 175,500 $RUN, untouched ✅ |

### The LP token — the one open question

`Terminal.setLpToken` expects a **fungible ERC-20** LP token, i.e. a Uniswap-V2-style pair, which is
what launchpads typically mint. **A Uniswap V3 position is an ERC-721 with a price range and will
not work here** — that would need a separate staker valuing each position.

Confirm which Pons / StonkBrokers use before mainnet; it is the only answer that would change this
contract. `MockLpToken` exists solely so the LP pool is exercisable on a chain with no DEX; it mints
freely to anyone and must never be deployed to mainnet. `setLpToken` is only callable while the LP
pool is empty, so no one's stake can be stranded behind a swap.

$AUG itself needs no "launch" mechanism — its full supply already exists, including the 5,000,000
(5%) launch seed the spec earmarks for bootstrapping liquidity. Launching means creating a pair and
depositing that seed alongside the other side of the market.

## Phase 6 — The Fixer

Two loan products, plus a real protocol reserve.

| | $RUN against a Stock//Runner | $AUG against an unused Augment |
|---|---|---|
| funded from | Black Market pool | ProtocolReserve |
| opening LTV | 50% of the pool's sell quote | 50% of the Augment's tier price |
| cost | upfront ETH rate = the pool's current sell fee tier; **no accruing interest** | linear 25% APR |
| LTV drifts because | the pool quote moves as units trade | interest accrues (collateral value is fixed by tier) |
| Iced at | 70% LTV **or** term expiry | 70% LTV (~1.6 years at 25% APR) |
| on repay | principal returns to the pool | principal to reserve, **interest burned** |

### Why the Black Market had to be redeployed

The spec is explicit that $RUN loans "draw from and repay into the Black Market's own liquidity pool
rather than a separate reserve, which keeps $RUN supply genuinely fixed." The deployed market had no
lending entry point and no generic execute, so a redeploy was unavoidable. **3,000,000 $RUN is
stranded in the old market** — it has no withdraw function, deliberately.

`maxLendBps` (default 50%) caps how much of the pool the Fixer may borrow. Not in the spec — a
safety rail, because without it lending could drain the pool's $RUN and `sell` would start reverting,
stranding operators who expect a floor bid.

### Icing seizes control, not ownership

An Iced position freezes (Augment interest stops accruing at that instant) but the borrower can
still repay and redeem right up until the collateral is disposed of. Disposal is a separate,
owner-gated step so a brief price dip doesn't cost an operator their unit with no chance to react —
and it is the natural handoff to the Chop Shop in phase 7. Seized Runners go to the Black Market
pool; seized Augments to the reserve.

### Live walkthrough

**Runner loan** (oracle temporarily set to 5e10 wei/$RUN so the ETH rate fit the deployer's balance,
which also put it in the 25% tier):

| Check | Value |
|---|---|
| pool quote / draw | 975,000 → **487,500 $RUN** (50%) ✅ |
| upfront rate | 0.006094 ETH → RevenueSplitter ✅ |
| unit | escrowed by the Fixer, LTV 5000 bps ✅ |
| repay | unit returned, `totalLent` 0, pool liquidity back to 2,000,000 ✅ |

**Augment loan**: bought a loose NVDA, drew **250 $AUG** (half of 500), LTV 5000 bps, collateral
escrowed, `reserve.outstanding()` 250 ✅

### Note on testnet ETH

The upfront rate is real ETH. At a realistic $RUN price (1e12 wei/$RUN, a unit ≈ 1 ETH) the rate on
one loan is ~0.073 ETH — more than the deployer held. Top up from
`faucet.testnet.chain.robinhood.com` before exercising Runner loans at realistic prices, or keep the
oracle low.

## Phase 7 — The Chop Shop

### Chainlink VRF is NOT available on Robinhood Chain

Verified two ways. Chainlink's VRF v2.5 supported-networks list covers Arbitrum, Avalanche, BASE,
BNB, Ethereum, OP, Polygon, Ronin and Soneium — Robinhood Chain is absent. On-chain probes found no
LINK token and no VRF coordinator at any canonical address.

What **is** live on Robinhood Chain is **CCIP, Data Feeds and Data Streams**, including tokenized
equity feeds for NVDA/GOOG/AAPL. That matters for phase 8's Drop and for eventually replacing
`TestnetRunPriceOracle` — but none of it provides randomness.

So entropy sits behind `IRandomnessSource`, with `CommitRevealRandomness` as today's implementation.
When VRF lands, write an adapter and call `ChopShop.setRandomnessSource`. Nothing else changes.

### `block.prevrandao` is not random here

The mixHash on this chain is a structured Arbitrum L1-info encoding — byte-identical across hundreds
of consecutive blocks. Anything depending on it is predictable.

**Consequence for `BlackMarket.buyRandom` (accepted, not fixed):** a contract caller can compute
which unit it would draw and revert until it gets the one it wants, obtaining "specific" selection
at the 10% random-unit price instead of 15%. An EOA cannot. Fixing it needs commit-reveal, which
would make buying a two-transaction flow. Documented in the contract.

### The odds curve (the spec's open item)

    p(win) = V / (V + B)

V = declared USDG value, B = backing. Verified live:

| backing | p(win) | entry |
|---|---|---|
| 0 | 100% | 1,300 USDG |
| 500 | 66.7% | 866.6 |
| 1,000 | 50% | 650 |
| 3,000 | 25% | 325 |
| 9,000 | 10% | 130 |

Entry = expected value + 30%; 10% of it is revenue. Backing floor is 25% of declared value, so a
built unit can't be listed at trivial backing. Declared value is self-policing — understate it and
your item is easy to win; overstate it and rollers won't play.

### Two bugs found by testing live, not in Foundry

**1. L1 vs L2 block numbers.** Solidity's `block.number` on Arbitrum returns the **L1** block number,
while block hashes are indexed by **L2** number. The first `CommitRevealRandomness` stored an L1
target (11,467,756) against an L2 head of 99,642,594, so `blockhash(target)` was always zero and no
roll could ever resolve. Foundry hides this because the local EVM uses one number for both. Fixed by
routing every read through ArbSys, and covered by a regression test that etches a mock ArbSys with a
deliberately offset block number so the two can never be conflated again.

**2. Swapping the randomness source stranded in-flight rolls.** The replacement source knew nothing
of the old request id, so the roll could neither resolve nor expire and the listing stayed closed
behind it. Each roll now pins the source it committed against; a swap only affects new rolls. Also
covered by regression tests.

### Live walkthrough

Listed a loose NVDA at 1,000 USDG declared / 1,000 backing (p = 50%), entry 650 USDG:

| Check | Value |
|---|---|
| `targetBlock` | 99,677,123 against an L2 head of 99,677,150 — an L2 number ✅ |
| ready in the roll's own block | false ✅ (the whole point) |
| ready two blocks later | true, randomness non-zero ✅ |
| resolve | **Won** ✅ |
| revenue split | 39 / 13 / 13 USDG = exactly 60/20/20 ✅ |
| claim TakeItem | NVDA to the roller, shop balance 0 ✅ |

### Honest limitation

A single sequencer produces these blocks, so it could in principle influence the target hash. That
is a real trust assumption and precisely why the source is swappable rather than hardcoded. It is
still strictly better than same-transaction pseudo-randomness, which the caller can simply compute
and reject.

## Phase 8 — The Drop

The payoff every other mechanic feeds, and the last phase. Protocol revenue becomes real-world
assets in Stock//Runner wallets, split across every **eligible bay by weight**.

### How a Drop runs

1. `openDrop()` — pulls the 60% bucket, plus anything a previous Drop couldn't deploy.
2. `accumulate(dropId, count)` — walks the collection in batches, snapshotting eligible bay weights.
3. `finalize(dropId)` — **one aggregate purchase per ticker**, then opens the claim window.
4. `claim(dropId, tokenId)` — pull-based, delivering into the unit's ERC-6551 wallet.
5. After the window: `sweepUnclaimed` sells what nobody collected, `executeBuyback` deploys it.

Every step is permissionless. Weights are read from the StockRunner and never supplied by anyone, so
a keeper chooses only *when* a Drop fires, never who earns from it.

### Live walkthrough (drop #1)

The 60% bucket had been accruing since phase 4: **175,500 $RUN**.

Unit #1 carried two eligible bays — NVDA (tier 3, 1.5x) and JNJ (tier 1, 1.0x), total weight 2.5x:

| Check | Value |
|---|---|
| tickers purchased | 2 aggregate buys for 2 tickers ✅ |
| NVDA slice | 175,500 × 1.5/2.5 = **105,300** ✅ |
| JNJ slice | 175,500 × 1.0/2.5 = **70,200** ✅ |
| claim (152,162 gas) | both assets delivered to TBA `0x93F5…0055` ✅ |
| operator balance | **0** — assets go to the unit, not the wallet ✅ |
| claim deadline | Sunday 2026-08-16 23:00 UTC = exactly 1h before the next Monday boundary ✅ |
| skipped / buyback | 0 / 0 — nothing left undeployed ✅ |

Capacity and tier drove the split exactly as the spec describes.

### The dust floor (the spec's other open item)

Left "pending real gas measurements". Measured: gas here is **0.01 gwei**, so a claim costs about
**0.0000015 ETH** and `dustFloor()` returns 1,500,000,000,000 wei. Implemented against **live**
`tx.gasprice` rather than a constant, so it tracks conditions. Below-floor amounts are held as
`dustCredit` and compound until worth collecting — never sold at window close, matching the spec's
distinction between dust and abandonment.

### Unavailable tickers

`IRwaVenue.buy` returning zero means the bay is skipped for that cycle and its share rolls into the
next pool — no substitute, no fallback holding. Covered by a test that delists a ticker mid-Drop and
asserts the carried amount lands in the next pool.

### A bug the tests caught

`claim` originally set the `claimed` flag *before* reading `claimable()`, which returns zeros once
that flag is set — so it closed the claim and delivered nothing. Three tests failed on it. Fixed by
reading the allocation first. `sweepUnclaimed` already had the correct order.

### Mainnet path

`MockRwaVenue` mints stand-ins at a settable price and must never ship. Implement `IRwaVenue` against
real Robinhood Stock Token liquidity, priced by **Chainlink Data Feeds — which are live on Robinhood
Chain** — and call `Drop.setVenue`. The Drop itself needs no change.

## Minting gate (added post-phase-8)

`StockRunner.mint()` originally had one condition — the 333 cap — so the mint was live the instant
the contract was deployed. Withholding the UI is not a control: the contract is public and
deployment-watching bots act on it.

`mintingOpen` now gates it, defaulting to **closed**. `openMinting()` is owner-only and **one-way** —
there is no close function. A closeable mint is a lever over holders, and an operator who can halt
minting at will is an operator who can be pressured to.

`DeployPhase2` opens it automatically on testnet only and hard-refuses to do so on mainnet, so the
launch sequence is: deploy → $RUN trades → site live with minting visibly shut → `openMinting()`.

> **The deployed testnet StockRunner (`0x7d17…307B`) predates this change** and has no
> `mintingOpen()`. The site's MintStatus fails closed on an undefined read, so it correctly shows
> "mint closed" against it. A redeploy is needed to exercise the open state on testnet.
