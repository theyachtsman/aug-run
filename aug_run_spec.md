# AUG//RUN

A cyberpunk RWA protocol on Robinhood Chain.

---

## Origin

AUG//RUN Industries was a robotics and financial-automation company. Their product: Stock//Runners — semi-autonomous androids built to manage real-world asset portfolios for corporate clients, chasing yield across equities, ETFs, and other tokenized real-world assets so no one had to watch the market by hand.

Then something happened — never fully explained, and it doesn't need to be. The technology was restricted. The company disappeared, officially. Its Stock//Runners didn't. Recovered, reverse-engineered, and passed hand to hand through the black market ever since, the same firmware, the same terminology, and the same appetite for real-world yield survives in every unit still active today.

Nobody owns AUG//RUN anymore. Everyone running a Stock//Runner is, in a sense, still running it.

---

## The Stock//Runner

The bearer NFT. Every Stock//Runner has its own ERC-6551 wallet — the same architecture AUG//RUN built for autonomous portfolio management. "Stock" in both senses: factory-default configuration, and the actual stock market it was built to trade.

A Stock//Runner is an android that was taken — physically repossessed off the street, then hacked and wiped back to a fresh, factory-default state, stripped of whatever corporate lock it shipped with. That reset is what "stock" means here: not new, just clean.

From there it has no type. It doesn't become a kind of unit until it's augmented at the Ripperdoc. Load it with volatile tech-sector Augments and it reads as one kind of build; load it with steady blue-chip holdings and it's a completely different one — same unit, entirely different identity, purely a function of what's installed. No class chosen upfront, no archetype step at mint. A Stock//Runner becomes whatever the streets make it.

Bought and sold at the Black Market.

---

## Collection Supply

**333 Stock//Runners.** A permanent maximum — a finite population of recovered corporate units. Once all 333 are activated, there's no mechanism to create more.

Every Stock//Runner mints directly through the Black Market for 1,000,000 $RUN — no presale, no reserved allocation, no starting inventory, no whitelist. You mint a blank, factory-reset unit and become its operator.

At 333 units, genesis activation commits at most 333,000,000 $RUN — **33.3% of total $RUN supply**. The remaining ~667,000,000 stays in circulation for loans, staking, and trading rather than being locked into NFT creation.

**Why 333.** Scarcity here comes from history, not headcount. Every unit starts on equal footing; what it becomes is entirely a function of its operator. Augments change its configuration, Expansion Modules raise its capacity, and every Drop, every position, every week of runtime accumulates into a visible record — including unrealised PnL on everything currently in its wallet. Two units that took identical Drops can be worth different amounts because one operator picked tickers that ran and the other didn't. Performance is part of the record, not just accumulation.

That makes the Black Market a market for proven machines. Mint a blank unit, operate it, build its record, sell the finished machine — the buyer inherits the history along with the hardware. The operator moves on. The Runner keeps its record.

**Genesis and secondary are separate economies.** Genesis: a blank unit for 1,000,000 $RUN. Secondary: an existing unit, priced for whatever configuration, history, and performance it's built up. Once the 333 are gone, secondary is the only way in.

There are only 333 Runners. The question was never which one you minted. It's what you turned it into.

---

## Rarity

**Models and units.** The 333 are drawn from **10–12 model lines**. AUG//RUN was a manufacturer, not a workshop — a production run means model lines with many units each, not 333 one-off builds. Each model is a distinct android design; each NFT is a **unit** of that model carrying its own serial. Roughly 33 units per model, equal counts.

Mint #0417 and you hold one unit of, say, the MK-II line — about 32 other operators hold different units of that same design. What separates yours from theirs is entirely what you install and what it earns.

**Every unit mints at identical rarity.** No model is scarcer than another, and no unit gets a rarity tier, trait score, or mechanical advantage at genesis. Model gives a unit identity; it does not give it value.

This is the load-bearing decision behind the whole economy. Assigning genesis rarity would create a second scarcity axis competing with the first, and the two would pull against each other. A visually rare unit would be scarce *and* passive — holding it costs nothing, augmenting it risks capital without improving what makes it rare. A built-out unit is scarce *and* active. On effort-adjusted returns the passive one wins, so rational holders would floor-price the rares and never visit the Ripperdoc. The augmentation economy would exist and nobody would enter it.

Flat rarity makes the record the only axis. What separates two units six months in is entirely what their operators did.

**Two consequences:**

- **Genesis is genuinely uniform.** All 333 mint at the same price with nothing to snipe, no rarity-checking, no bot advantage. That matters for a launch with no whitelist.
- **Models must be siblings, not a hierarchy.** With only 10–12 designs, operators can compare them side by side, so any model reading as obviously superior collects a taste premium the spec never assigned. Vary silhouette, posture, and wear — not quality. Equal counts keep supply rarity off the table; sibling design keeps aesthetic rarity off it too.

Optional: a light within-model variant layer (finish, palette, wear pattern) so two units of a model aren't pixel-identical. Only worth doing if variants stay evenly distributed and non-hierarchical.

---

## Augments

ERC-1155 items, each bound to a specific real-world asset (NVDA, AAPL, SPY, etc.). A unit earns based on which Augments are seated at each Drop.

Augments display as **badges**, not composited artwork — an installed optic reads as a labelled Optic badge tied to its ticker, with the hardware implied rather than drawn onto the android. This frees every model to be its own piece of art instead of forcing a shared base body that layers would have to align to.

### The catalog

**Twelve distinct Augments at launch, one ticker each.** No bundled Augments — a bay holds exactly one asset.

Bundling was considered and rejected. It would turn each bay into a mini-portfolio, muddy the badge's meaning, complicate PnL display, and force the contract to split purchases within a bay. More to the point, **diversification is already available through ticker choice** — index and sector ETFs are bundles. An operator wanting spread in one bay seats a broad index; one wanting concentration seats a single name. Same mechanic, no extra machinery.

**Duplicate tickers across bays are explicitly allowed.** An operator can run the same Augment in all three bays — a maxi build. It carries no mechanical advantage: every bay earns the same weighted share regardless of what's seated, so concentration means identical expected value at triple the variance. That's a real bet, made deliberately, and it's the kind of decision that makes a record worth reading later. It also creates legible archetypes — a maxi is recognizable at a glance, and archetypes are how a collection develops its own language.

Concentration does carry one cost: **tier is a property of the Augment**, so a maxi build is locked to that ticker's tier across every bay. A diversified build can pick tier per bay. Concentration buys conviction and gives up flexibility.

### Catalog size and the build space

With 12 Augments, duplicates permitted, and a three-bay ceiling, there are 455 possible bay configurations; across ~11 model lines that's roughly **5,000 possible unit presentations — about 15× the population.**

The practical effect: at one Augment, duplicate builds are common, since operators cluster on recognizable tickers. At three bays the space is wide enough relative to the crowd that nearly every fully-built unit ends up genuinely one-of-one.

**Building a unit out isn't only about yield — it's how a unit becomes unique.** Fewer Augments (say 6) collapses the space toward the population size and makes duplicates unavoidable even at max capacity. Many more makes the shop feel uncurated without adding anything that matters.

### Choosing the twelve

Ticker selection is deferred to development and constrained by **what's genuinely tokenized and liquid as Stock Tokens on Robinhood Chain at that time.** Committing to specific names now risks building the catalog around an asset that turns out thin or unavailable, which becomes a delisting problem later.

**The catalog is designed to expand.** As Robinhood Chain lists more RWAs, new Augments can be added to the Ripperdoc without touching any other mechanic — the weight math, bay ceiling, and Drop allocation are all catalog-size agnostic. Twelve is the launch number, not a permanent cap.

**Tier and risk must stay independent.** This is the one hard constraint on selection. If tier correlated with volatility, buying maximum weight would force maximum variance, and conservative operators would be structurally penalised for playing carefully. Instead, each tier should span the risk spectrum:

| Tier | Weight | Composition |
|---|---|---|
| **Tier 1** | 1.0x | broad index · defensive · value · one high-beta |
| **Tier 2** | 1.25x | broad tech · mega-cap · defensive · one volatile |
| **Tier 3** | 1.5x | mega-cap momentum · volatile · stable mega · one alternative |

That gives two genuinely independent axes: **tier buys weight, ticker chooses risk.** A cautious operator can max tier and still hold steady names. An aggressive one can run high-beta cheaply at tier 1. Neither strategy dominates the other, and the interesting question stays open.

### Tiers

Tier sets both $AUG cost and allocation weight at the Drop. A higher-tier Augment costs more and earns more; the ticker seated in it still determines *which* asset that larger share buys.

| Tier | Price | Weight | Cost per 1.0x |
|---|---|---|---|
| Tier 1 | 100 $AUG | 1.0x | 100 |
| Tier 2 | 250 $AUG | 1.25x | 200 |
| Tier 3 | 500 $AUG | 1.5x | 333 |

**Tier weights: 1.0x / 1.25x / 1.5x.** Deliberately modest, and deliberately *worse per dollar spent* — a tier-3 Augment costs meaningfully more than a tier-1 but earns only half again as much.

That looks irrational until you remember bays are capped at three. **Bay slots are the scarce resource, not $AUG.** An operator with all three filled can only grow by making each bay denser, so paying a premium for weight per slot is correct precisely because slots run out. The three-bay ceiling is what makes premium tiers rational.

The pricing makes that tradeoff explicit. Tier 3 costs 3.3x what tier 1 does for 1.5x the weight — badly inefficient per dollar, and correct anyway once bays run out. An operator with spare bays should always fill them with tier 1 first; only a maxed-out operator should be buying tier 3.

Tier 1 at 100 $AUG also sits well below the 500 $AUG Expansion Module, which keeps the early sequence sensible: a new operator can afford hardware for the free bay long before they can afford a second bay. Nobody ends up buying capacity they have nothing to put in.

Note tier 3 and an Expansion Module cost the same 500 $AUG — a deliberate and interesting fork. That $AUG either upgrades an existing bay from 1.0x to 1.5x, or opens an entirely new bay worth 1.0x on its own. Capacity wins on raw weight; density wins if you're already full.

Tiering is tied to price, not ticker — no ticker is inherently better than another.

### Cost and swapping

Each Augment costs $AUG. **Half burns permanently; half funds the $AUG protocol reserve**, which backs the Fixer's $AUG loans and Chop Shop redemptions. Augment sales are the reserve's primary income — the more the Ripperdoc sells, the deeper the lending pool gets.

Swapping means selling the old Augment first. Resale value is half what you paid, credited against the new one's cost. Pay 100 $AUG for a tier-1 Augment, move to a tier-2 at 250, and the swap costs 200 $AUG.

**Once seated, an Augment is bound to that unit.** It cannot be moved to another Stock//Runner, even one the same operator owns. The only ways out of a bay are selling it back to the Ripperdoc or putting it on the table at the Chop Shop — in both cases the Augment leaves the operator's hands entirely.

Binding is what keeps tenure honest. If Augments could shuttle between units, an operator with five Runners could farm tenure on a spare and transplant it into whichever unit they were about to sell. Tenure has to be non-portable for "held this build for two months" to mean anything.

Augments that have been purchased but never seated remain loose and transferable, and those are what the Fixer accepts as $AUG collateral.

### Rebinding cadence

Augments can be changed between Drops, but **an Augment only earns if it was seated for the entire cycle** — present at both the open and the close. Install mid-cycle and it earns nothing until the next full one. Sell mid-cycle and it forfeits that cycle entirely.

**One rebind per bay per cycle.** A changed bay is locked until the next Drop.

This kills an otherwise obvious exploit: without seasoning, an operator could buy Augments immediately before a Drop, collect, and sell them straight back — paying only the 50% resale spread to rent yield they never committed to. Full-cycle presence means the only way to earn is to actually hold through the period.

It also makes rebinding a real decision. Swapping costs a cycle, so operators change builds when they mean it.

### Tenure weighting

An Augment's weight **grows the longer it stays seated**. Linear and legible: **+0.0625x per cycle for eight cycles, from 1.0x to a 1.5x ceiling** — about two months of continuous service to max out.

Linear on purpose. An operator can look at a bay and know what next week is worth without modelling a curve, and there's no cliff where one missed decision destroys a position.

**Rebinding resets that bay's tenure to zero.** The new Augment starts at 1.0x and climbs again.

**Tenure survives a sale.** When a unit changes hands, every bay keeps its accumulated tenure — the buyer inherits earning power, not just a history log. That's a large part of what a built unit's premium actually buys, and it's what makes "the machine remembers" literally true rather than decorative.

This creates a constraint the buyer has to respect: **rebinding still resets, even for a new owner.** Buy a unit with three bays at full tenure and immediately swap the tickers, and you've destroyed exactly what you paid the premium for. A tenured unit is worth what it's worth *as configured*. Keeping it means honouring the previous operator's build; changing it means starting the eight-cycle climb over. That tension is the whole secondary market in one sentence.

This is the counterweight to tier. Tier is bought; tenure is only earned by leaving something alone. A one-bay operator running a mid-tier Augment held two months can out-earn someone who bought top-tier last week — capital and patience are separate paths, and neither dominates.

It's also the strongest anti-churn mechanic in the protocol: an operator who chases whatever ticker ran last week permanently sits at base weight.

---

## Expansion Modules

The addon that expands what a unit can carry. **The Module is the item you buy; a bay is the slot it opens.**

A Stock//Runner ships with **one bay, free, built into the frame**. Each Module installed adds another, and each bay holds one Augment.

**500 $AUG each.** Same split as Augments — half burns, half funds the protocol reserve.

**Maximum two Expansion Modules per unit — a three-bay ceiling.** Every unit shares that ceiling, which keeps capacity from becoming a hidden rarity axis. A fully-built unit is fully built, full stop; no unit can out-scale another on slots. What separates two maxed units is which Augments are seated and what the record looks like.

Three bays also keeps maxing out an achievable goal rather than a whale-gated one.

---

## $RUN

AUG//RUN's old internal currency, baked into every unit's firmware — impossible to fully strip out even after the company vanished. The fixed unit of exchange at the Black Market: **1,000,000 $RUN buys a Stock//Runner.**

**Total supply: 1,000,000,000 $RUN.**

Priced in the token itself, not pegged to a dollar figure. A unit's effective USD cost moves with $RUN's own market price — buying one always costs the same 1,000,000 $RUN regardless of where that price sits, which means minting demand and $RUN demand are the same act. The opening dollar price is whatever initial liquidity is calibrated to at launch.

---

## $AUG

The street economy's own currency, grown among vendors and operators rather than corporate-issued. Stake it at the Terminal for a cut of protocol revenue; burn it at the Ripperdoc for Augments and Modules. Where $RUN is what's left of the old company, $AUG is what the underground built on top of it.

**Total supply: 100,000,000 $AUG**, split:

- **80,000,000 (80%) circulating** — Augment purchases, staking, organic trading.
- **15,000,000 (15%) protocol reserve** — funds Chop Shop redemptions and Fixer $AUG loans. Kept lean since early borrowing is expected to be minimal; grows over time as Augment sales feed it.
- **5,000,000 (5%) launch seed** — bootstraps initial staking rewards and Black Market $AUG liquidity.

---

## Runners Row

The marketplace itself. An industrial strip of converted loading bays, corrugated shutters, and service gantries where every vendor keeps a shopfront — the Black Market, the Ripperdoc, the Fixer, and the Chop Shop all operate off the same row, with the Terminal kiosk mounted along it. Where salvaged units and stripped hardware change hands, and the hub every operator passes through to reach anything else.

---

## The Black Market

Where Stock//Runners change hands, run by **the Fence**. Fixed-price mint and market, priced in $RUN.

**Genesis:** 1,000,000 $RUN activates a blank unit. Every mint happens one at a time, directly through the Black Market — no bulk event, no separate allocation.

**Secondary:** once all 333 are activated, the Black Market is purely secondary — existing units changing hands, priced for whatever history and configuration they've built.

**Fees.** Purchase is 10% of the $RUN TWAP for a random unit, 15% for a specific one. Sell fee is tiered by that same TWAP — 25% below a 0.1 ETH floor, 15% between 0.1 and 1 ETH, 10% above 1 ETH.

**Split:** 60% funds the Drop, 20% to $AUG stakers, 20% to $AUG liquidity providers.

### Royalties

A **5% ERC-2981 royalty** on unit sales that happen outside the protocol, split the same 60/20/20.

This is a leak patch, not a revenue grab. Black Market fees only fire on trades routed through it — a unit listed on an external marketplace would otherwise change hands with the ecosystem earning nothing, and since Black Market fees run 10–25% there's real incentive to trade elsewhere. The royalty means a unit changing hands funds every other unit regardless of venue.

The royalty sits deliberately below the Black Market's own fee tier. Trading on the Row should still be cheaper; the royalty exists so leaving isn't free, not so it's punished.

---

## The Ripperdoc

Buy Augments and Expansion Modules. The Ripperdoc doesn't ask where your $AUG came from.

**The used bin** runs alongside fresh stock: Augments pulled off liquidated and traded-in units, sold on without the burn. Cheaper entry, no guarantees, limited quantities. Restocks daily.

---

## The Fixer

**Borrow $RUN against a Stock//Runner.** Deposit it, set the term, pay an upfront rate in ETH pegged to the Black Market's current sell fee. Loans draw from and repay into the Black Market's own liquidity pool rather than a separate reserve, which keeps $RUN supply genuinely fixed and couples borrowing to the pool's TWAP.

**Borrow $AUG against an unused Augment.** Draw half its $AUG value at a fixed 25% APR, funded from the $AUG protocol reserve. Fall to 70% loan-to-value and you're **Iced**. Interest paid back in is burned.

---

## The Chop Shop

Run by **the Scrapper**. Deposit a Stock//Runner, an Augment, or a holding, backed by an amount of USDG. **The less you back it with, the better everyone's odds on a roll** — backing is how a depositor sets the difficulty.

Entry costs the expected value of the roll plus 30%. 10% of that payment is taken as revenue.

On a win, the roller chooses:
- **Keep the backing** — USDG fee refunded
- **Cash out** — 85% of the backing
- **Convert** — 90% of value in $RUN or $AUG

The remainder is taken as revenue in each case.

**The table rotates daily** — new items, new backing, new odds.

---

## The Terminal

A wall-mounted kiosk on Runners Row — no vendor, no negotiation. **Stake $AUG** for a cut of protocol revenue, or provide $AUG liquidity for the same. The 20%/20% staker and LP shares of every fee split are claimed here.

Deliberately unstaffed. Every other stop involves someone taking a position across a counter — the Fence moving inventory, the Ripperdoc installing hardware, the Fixer setting terms, the Scrapper running odds. Staking isn't a transaction with anyone. It's a machine that pays on schedule, so it gets a machine.

Keeping it out of the Fixer's booth is intentional: his shop is where operators take on risk, the Terminal is where they step out of it. Same currency, opposite intent.

Calibration happens at the Ripperdoc, not here — see below. Maintenance is something a person does to
your hardware across a counter; the Terminal is a machine that pays on schedule.

---

## The Daily Loop

The Drop is weekly, but a unit is worth checking on daily. Three layers do that work, and none punishes an operator for missing a day — the loop is built on opportunity, not obligation.

### Live position value

Every unit's wallet holds real tokenized equities, and those move whenever the market does. A unit running NVDA and SPY has a PnL that changes constantly, surfaced on Runners Row as the first thing an operator sees: today's move, lifetime PnL, and how the unit ranks against the collection.

Costs nothing to build, requires no transaction to consume, and emerges from what the protocol already does rather than from an invented mechanic.

### Daily rotation

Two shops restock on a daily clock, turning browsing into a habit:

- **The Ripperdoc's used bin** refreshes daily. A tier-3 Augment might surface below fresh price on a Tuesday and be gone by Wednesday.
- **The Scrapper's table** rotates daily — new items, new backing, new odds.

Miss a day and you missed an opportunity, not a payout.

### Calibration

The daily sink. **5 $AUG per unit per day at the Ripperdoc, adding +0.003x tenure.**

Seven daily calibrations add ~0.021x per cycle on top of the base 0.0625x, bringing a consistent calibrator to the 1.5x ceiling in **six cycles instead of eight** — roughly six weeks rather than eight.

Calibration never adds yield directly and skipping it never costs anything. Tenure advances at its normal rate regardless; calibration only accelerates it. Pure upside, no penalty — an operator who travels for two weeks returns to a unit exactly where it should be.

It's the only daily sink that reinforces the rest of the design rather than fighting it. A mechanic rewarding daily trading or rebinding would gut the tenure system anti-churn depends on. Calibration rewards daily attention to a build the operator already committed to, burns $AUG recurrently, and gives patient operators a way to be marginally more patient. Machines need maintenance.

---

## The Drop

Protocol revenue becomes real-world assets in Stock//Runner wallets. The payoff every other mechanic feeds.

### Cadence

**Weekly, anchored to Monday 00:00 UTC.** Every cycle opens and closes on that boundary, and the same clock governs rebinding, seasoning, tenure accrual, and the claim window.

One fixed anchor for everything means an operator never has to track more than one deadline. Note that 00:00 UTC lands at 8pm US Eastern during daylight saving and 7pm outside it — UTC is canonical, local time drifts.

Daily creates dust and constant gas overhead against tiny amounts; monthly is too slow to keep operators engaged with a build they're paying to maintain.

### What funds it

60% of Black Market fees, 60% of external royalties, and Chop Shop revenue accumulate into the Drop pool across the week.

The pool is whatever the protocol actually earned. **No minimum yield, no promised APY, nothing breaks at low volume.** Small revenue means small Drops, not failed ones.

### Allocation

The pool splits across every eligible bay **by weight** — not evenly, and not per unit.

```
bay weight = tier multiplier × tenure multiplier
bay share  = Drop pool × (bay weight ÷ total weight across all units)
```

**Three things drive earnings:**

- **Capacity** — how many bays. Up to 3x from Expansion Modules.
- **Tier** — how expensive the seated Augments are. Bought with $AUG. Independent of the ticker's risk profile.
- **Tenure** — how long they've been seated. Earned only by leaving them alone.

**The full spread.** A single bay ranges from 1.0x (tier-1, freshly seasoned) to 2.25x (tier-3 at full tenure). Across three bays, a fully built and long-held unit carries about **6.75x the weight of a bare one-bay unit running a fresh base Augment.**

That spread is intentionally restrained. Wider would let the top of the collection capture so much of each pool that stock units rarely clear the dust floor — leaving a tier of dead assets and hollowing out the Black Market floor. Every unit should earn something meaningful; built units should just earn considerably more.

It's also what makes two one-bay units genuinely different machines. One running a top-tier Augment held since launch earns 2.25x what its neighbour earns running base-tier swapped last week — same capacity, different operator.

**The ticker determines which asset, not how much.** Weight decides the size of a bay's share; the seated ticker decides what it's spent on. No ticker is mechanically better, so picking NVDA over SPY is a judgment call about performance rather than a solved optimisation — and the difference shows up later in PnL, not at the Drop itself.

### Execution

The protocol converts the pool into RWAs **in aggregate, one purchase per ticker** — all NVDA exposure bought in a single transaction, then divided among the bays running it. Twelve Augments means at most twelve purchases per Drop regardless of collection size.

**Delivery is pull-based.** The Courier doesn't deliver — he holds a package, and the operator comes to collect. Assets sit in escrow until claimed into the unit's wallet, with the operator paying their own gas.

### The claim window

Claimable from the moment a Drop fires until **one hour before the next Drop** — just under seven days.

**Anything unclaimed at expiry is sold, and the proceeds fund a $RUN buyback.** The value doesn't vanish and doesn't sit accumulating in escrow — it converts into buy pressure benefiting everyone still participating.

This is what makes a Stock//Runner an active position rather than a passive one. A unit whose operator doesn't show up doesn't just miss out; it funds the operators and holders who did.

It also means an unclaimed Drop can never be sold along with a unit. What's in the wallet at sale time is what the buyer gets — no hidden entitlement attached to a listing, which keeps Black Market pricing honest.

**Why $RUN.** It deepens the Black Market pool — also the pool the Fixer's $RUN loans draw from — and supports the token mint pricing is denominated in, reinforcing the loop where minting demand and $RUN demand are the same act. Stakers and LPs already receive 40% of every fee split, so directing buybacks to $AUG would concentrate value on the same participants twice.

### The dust floor

At low volume a unit's share can be worth less than the gas to claim it. Nobody should spend more collecting a Drop than the Drop is worth.

**A Drop is only escrowed if it exceeds the cost of claiming it.** Below that, nothing is escrowed — the amount rolls forward into that unit's next Drop and compounds until it's worth collecting. A stock unit early in the protocol's life might accumulate quietly for a month before its first claimable Drop; that's intended behaviour, not a failure state.

Measured against live gas cost rather than a fixed dollar figure, so it adjusts as conditions change.

**Dust and abandonment are different states:**

- **Below threshold** — never became claimable, so nothing expires. Rolls forward and compounds.
- **Above threshold, unclaimed** — was collectable and the operator didn't come. Sold at the window's close to fund the buyback.

Since allocation scales with capacity, tier, and tenure, a built-out unit clears the threshold considerably sooner than a stock one. In a low-revenue period, built units may be claiming weekly while stock units are still accumulating — a real advantage to capacity beyond raw yield.

### Unavailable tickers

If a bay's ticker is delisted or unavailable at purchase time, **the bay is skipped for that cycle** and its share rolls into the next pool. No substitute, no fallback holding.

The operator is expected to notice and plan around it. Rebinding takes effect the following cycle under normal seasoning, so a delisting costs at minimum one Drop and possibly two. That's deliberate — paying attention to what's seated is part of running a unit well.

---

## $RUN launch

$RUN goes to market via a **launchpad on Robinhood Chain, venue to be decided.** The mint cannot open until $RUN is tradeable, since genesis activation is denominated in it.

Sequencing matters more than venue: $RUN launches first, mint opens after. The launchpad is also a distribution channel — anyone who wants to mint has to acquire $RUN, so early buyers are pre-positioned holders rather than pure speculators.

One dependency worth holding onto: launching $RUN sets a clock. Once it trades, holders expect the mint, so the site and art should be finished before the token launches rather than after.

## Build roadmap

Robinhood Chain is a standard Arbitrum Orbit L2, fully EVM-compatible — Foundry, standard OpenZeppelin patterns, nothing chain-specific to work around.

- **Testnet:** chain ID `46630`, RPC `https://rpc.testnet.chain.robinhood.com`, faucet at `faucet.testnet.chain.robinhood.com`
- **Mainnet:** chain ID `4663`
- Native ERC-4337 support means gas sponsorship on genesis mints is cheap and worth using given the walk-up-and-mint design

Sequenced by dependency, each phase demoable before the next starts:

1. **Foundation.** $RUN and $AUG as fixed-supply ERC-20s.
2. **Stock//Runner core.** ERC-721 + ERC-6551 token-bound account per mint (standard reference registry, not custom). Genesis mint: pay 1,000,000 $RUN, get a blank unit with its own onchain wallet.
3. **Augments, Expansion Modules, the Ripperdoc.** ERC-1155s for both item types. Purchase, burn-half-to-reserve, resale-credit swap logic, tier weights.
4. **The Black Market.** Fixed-price mint/trade, TWAP-tiered fees, 60/20/20 split, ERC-2981 royalties. Most custom logic in the system — closer to a bonding curve than an off-the-shelf AMM.
5. **The Terminal.** $AUG staking, LP rewards.
6. **The Fixer.** $RUN loans from the Black Market pool, $AUG loans from the protocol reserve, liquidation at 70% LTV.
7. **The Chop Shop.** Needs verifiable randomness — confirm Chainlink VRF or equivalent is live on Robinhood Chain before designing this phase. Odds curve and backing constraints still to be defined.
8. **The Drop.** Aggregate RWA purchasing, weight calculation, escrow, claim window, buyback, dust floor.

**Phases 1–3 are enough for a real testnet walkthrough:** mint a blank Stock//Runner, gear it up, watch it change. That's the milestone worth hitting first.

---

## Open items

- **Chop Shop odds curve** — the relationship between USDG backing and roll probability, plus a backing floor tied to item value so a heavily-built unit can't be listed at trivial backing. Deferred to phase 7.
- **Launchpad venue** for $RUN.
- **Verifiable randomness availability** on Robinhood Chain — needs confirming before phase 7.
- **Dust floor threshold value** — pending real gas measurements on Robinhood Chain.
