# AUG//RUN — Claude Code build prompt (phases 1–3)

Paste this into Claude Code. `aug_run_spec.md` should be in the repo root — it's the source of truth. Anything here that contradicts the spec, follow the spec and flag it.

---

## What we're building

AUG//RUN is a cyberpunk RWA protocol on Robinhood Chain. Users mint **Stock//Runner** NFTs (ERC-721, each with its own ERC-6551 token-bound wallet), install **Augments** (ERC-1155, each tied to a real-world asset ticker) into **bays**, and expand capacity with **Expansion Modules**.

This build covers phases 1–3 only: tokens, the Stock//Runner core, and the Ripperdoc item system. **No Black Market AMM, no Fixer, no Chop Shop, no Drop distribution.** Those come later and should not be stubbed beyond what's needed to compile.

Goal: contracts deployed to Robinhood Chain testnet, plus a local web UI on localhost where I can connect my Robinhood wallet and exercise every function end to end.

---

## Environment

- **Chain:** Robinhood Chain testnet (Arbitrum Orbit L2, fully EVM-compatible)
- **Chain ID:** `46630`
- **RPC:** `https://rpc.testnet.chain.robinhood.com`
- **Explorer:** `https://explorer.testnet.chain.robinhood.com`
- **Faucet:** `https://faucet.testnet.chain.robinhood.com`
- **Toolchain:** Foundry (forge/cast/anvil). Standard OpenZeppelin contracts. Nothing chain-specific required.
- I have a Robinhood wallet with testnet funds already.

Start by confirming RPC connectivity and my wallet balance before writing contracts.

---

## Phase 1 — Tokens

Two fixed-supply ERC-20s. No mint function after deploy, no owner mint, no upgradeability.

**$RUN** — 1,000,000,000 total supply, 18 decimals.
**$AUG** — 100,000,000 total supply, 18 decimals.

$AUG needs a **burn** function, called heavily in phase 3.

For testnet only, add a faucet function on both that lets any address pull a fixed test allocation. Gate it behind a constructor flag or a separate `TestnetFaucet` contract so it cannot ship to mainnet. Make this obvious in the code — a comment block, not a subtle boolean.

---

## Phase 2 — Stock//Runner core

**ERC-721, hard cap 333.** No owner mint, no reserve, no allowlist. Every mint goes through the same path.

**Genesis mint:** caller pays exactly **1,000,000 $RUN** and receives one Stock//Runner. Approve-then-transferFrom. For this phase, transfer the $RUN to a treasury address held in the contract — the Black Market AMM that will eventually receive it is phase 4.

**ERC-6551:** every minted unit gets a token-bound account. Use the **standard reference registry and account implementation** (ERC-6551 reference deployment) — do not write a custom TBA. Deploy or point at the canonical registry on testnet; if it isn't deployed there, deploy the reference contracts yourself and note the addresses.

Expose a view returning a unit's TBA address given its token ID.

**Per-unit state:**
- `model` — assigned at mint from 11 model lines, equal counts (~30 per line, distribute the remainder deterministically). Model is cosmetic only, no mechanical effect. Assignment must not be gameable — no picking your model.
- `bayCount` — starts at 1, max 3
- Per-bay: seated Augment ID, tier, `seatedAtCycle`, `tenureCycles`

**Cycles.** Weekly epochs anchored to **Monday 00:00 UTC**. Implement as a pure function from `block.timestamp` to cycle number against a fixed genesis timestamp constant. Everything downstream keys off this, so it needs to be exact and unit-tested around boundaries.

Add a testnet-only function to fast-forward the effective cycle so I can test tenure and seasoning without waiting weeks. Same gating rules as the faucet.

---

## Phase 3 — Augments, Expansion Modules, the Ripperdoc

**ERC-1155** for both item types.

**Augments** — 12 distinct at launch, one ticker each, across three tiers:

| Tier | Price | Weight |
|---|---|---|
| 1 | 100 $AUG | 1.0x |
| 2 | 250 $AUG | 1.25x |
| 3 | 500 $AUG | 1.5x |

Use placeholder tickers for now; real ones depend on what's liquid on Robinhood Chain at launch. **The catalog must be extensible** — adding Augments later cannot require redeploying or touching weight math.

**Expansion Modules** — 500 $AUG, max 2 per unit, each opens one bay.

**Purchase split:** exactly half of every $AUG payment is **burned**, half goes to a **protocol reserve** address. Applies to Augments and Modules alike.

**Seating rules — these are the core logic, get them exactly right:**

1. An Augment can only be seated into an **open bay** on a unit the caller owns.
2. **Once seated, an Augment is bound to that unit permanently.** It cannot be moved to another unit, including one the same operator owns. This is not negotiable — it's what makes tenure meaningful.
3. The only ways out of a bay: **sell back to the Ripperdoc** (returns half the purchase price as credit) or the Chop Shop (phase 7, not built).
4. **Swap = sell old, buy new**, paying only the difference. Selling a 100 tier-1 and buying a 250 tier-2 costs 200 $AUG net.
5. **Duplicate tickers across bays are allowed.** Three of the same Augment on one unit is valid.
6. **One rebind per bay per cycle.** A changed bay is locked until the next cycle.
7. Augments **purchased but never seated** stay loose and transferable. Only seated ones bind.

**Weight math:**

```
tenureMultiplier = 1.0 + 0.0625 * min(tenureCycles, 8)   // caps at 1.5x
bayWeight        = tierMultiplier * tenureMultiplier
unitWeight       = sum of all seated bay weights
```

Use fixed-point (1e18) throughout, no floats.

**Seasoning:** an Augment only counts as eligible if seated at both the open and close of a cycle. Seated mid-cycle means it earns nothing until the next full one. Implement the eligibility check now even though the Drop that consumes it is phase 8.

**Tenure:**
- Accrues +1 per full cycle seated
- **Resets to 0 on rebind** — including when a new owner rebinds after buying the unit
- **Survives NFT transfer.** Tenure travels with the unit. Do not reset on `transferFrom`. This is deliberate; it's what a built unit's resale premium buys.

**Calibration:** 5 $AUG per unit per day at the Ripperdoc, adds +0.003x to that unit's tenure multiplier. One per unit per day. Same burn/reserve split. Skipping never penalises — it only accelerates.

---

## Local test UI

A minimal web app on localhost. **Function over form** — no styling effort, this is a test harness, not the real site. That gets designed separately.

Needs to:
- Connect my Robinhood wallet, prompt to switch to chain 46630
- Show $RUN / $AUG balances, with faucet buttons
- Show current cycle number and time to next boundary
- Mint a Stock//Runner (approve + mint), show the resulting token ID, model, and TBA address
- List my owned units with bay state, seated Augments, per-bay weight, unit total weight
- Buy Augments and Expansion Modules from a catalog
- Seat, sell back, and swap Augments — with clear errors when a rule blocks the action
- Calibrate
- A dev panel: advance cycle, so tenure accrual is testable immediately

Vite + React + wagmi/viem is fine. Read ABIs from Foundry build output rather than hand-copying them.

---

## Testing

Foundry tests covering at minimum:
- 333 cap enforced; mint 334 reverts
- Mint fails without sufficient $RUN or approval
- Cycle boundary math exactly at Monday 00:00 UTC, either side
- Seating into a locked bay reverts
- **Moving a seated Augment between two units the same wallet owns reverts** — call this out explicitly
- Rebind resets tenure to 0
- **NFT transfer preserves tenure** — assert non-zero after transfer
- Tenure multiplier caps at 1.5x after 8 cycles, doesn't exceed
- Half of every purchase burns; total supply drops by exactly that
- Duplicate Augments across three bays succeeds
- Two rebinds on the same bay in one cycle reverts
- Seasoning: seated mid-cycle is ineligible that cycle, eligible next

---

## How to work

Build and verify **phase by phase**. Don't write all three then debug. After each phase: run tests, deploy to testnet, confirm on the explorer, tell me what to check in the UI before moving on.

Keep a `DEPLOYMENTS.md` with contract addresses per phase.

If something in the spec is ambiguous or you hit a design decision that isn't covered, **stop and ask** rather than guessing. Several rules here look arbitrary but are load-bearing — particularly Augment binding and tenure-surviving-transfer. If a rule seems wrong, flag it rather than quietly implementing what seems more sensible.

Start with phase 1.
