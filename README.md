# AUG//RUN

A cyberpunk RWA protocol on Robinhood Chain. See [aug_run_spec.md](aug_run_spec.md) — that document
is the source of truth. [augrun_dev_prompt_phases_1-3.md](augrun_dev_prompt_phases_1-3.md) scopes the
current build to phases 1–3.

**This build:** contracts deploy to Robinhood Chain **testnet**; the test UI runs on **localhost**.

## Security note — read before adding a key

This repository lives on a `fuseblk` mount (`user_id=0,allow_other`) where **`chmod` does not
persist** — every file in this directory reads as `rwxrwxrwx root root` no matter what mode is set,
and is therefore readable by any user on the machine.

**Never put a private key in this directory.** The deployer key lives at `~/.aug_run/.env`, mode
`0600`, on the real filesystem. `bin/deploy.sh` sources it from there and refuses to run if the mode
isn't `600`. See [.env.example](.env.example).

## Setup

```bash
# Foundry (already installed at ~/.foundry/bin)
export PATH="$HOME/.foundry/bin:$PATH"

forge build
forge test
```

## Deploying

```bash
# one-time: put your throwaway testnet key in place
cp .env.example ~/.aug_run/.env
chmod 600 ~/.aug_run/.env
$EDITOR ~/.aug_run/.env        # set PRIVATE_KEY

bin/deploy.sh phase1 --dry     # simulate, no broadcast
bin/deploy.sh phase1           # broadcast to RH testnet

NETWORK=localhost bin/deploy.sh phase1   # against a local anvil instead
```

Addresses are recorded in [DEPLOYMENTS.md](DEPLOYMENTS.md).

## Test UI

```bash
cd ui
npm install --ignore-scripts     # first time only
npm run dev
```

Serves on **http://localhost:3333** and on every interface, so it is reachable from any browser on
the LAN (e.g. `http://10.0.0.88:3333`). The harness holds no keys — every transaction is signed by
the visitor's own wallet — but note it *is* exposed to your whole network while running.

ABIs are read straight out of Foundry's `out/` by `ui/scripts/extract-abis.mjs`, which runs
automatically before `dev` and `build`. Nothing is hand-copied; re-run `forge build` and the UI picks
up the new ABI.

### Two environment traps on this drive

Both are worked around already; they are recorded here because they will bite again.

1. **The mount path contains a colon** (`…-0:0-part1`). `PATH` is colon-separated, so npm's
   `node_modules/.bin` entry gets split into two invalid paths and *no locally installed binary
   resolves by name* — `vite: not found` even though the symlink is fine. The `ui` scripts therefore
   invoke `node node_modules/vite/bin/vite.js` directly rather than relying on `PATH`. Any other
   tool run from this drive will hit the same thing.
2. **`chmod` does not persist** (fuseblk, `user_id=0,allow_other`). Hence keys living in
   `~/.aug_run/.env`, never here.

`npm install` needs `--ignore-scripts` because `bufferutil` / `utf-8-validate` (optional native deps
of `ws`, pulled in via the MetaMask connector) fail to build without `node-gyp-build` on PATH. Both
have pure-JS fallbacks, so nothing is lost.

## Two front ends

| | Port | Purpose |
|---|---|---|
| `site/` | **3000** | The production website — Next.js App Router, Runners Row as the hub |
| `ui/` | **3333** | Dev harness — function-over-form, drives every contract call directly |

```bash
cd site && npm install --ignore-scripts && npm run dev   # production site  :3000
cd ui   && npm install --ignore-scripts && npm run dev   # dev harness      :3333
```

Both bind `0.0.0.0` and read ABIs straight from Foundry's `out/`. The site targets testnet until
`NEXT_PUBLIC_CHAIN=mainnet` is set; addresses live in `site/lib/addresses.ts`.

### The production site is a point-and-click game

Runners Row is a **scene**, not a nav bar. A painted backdrop of the whole strip; click a stall and a
90s dither dissolve wipes to the shop interior with the vendor layered over it. Vendors have dialogue
boxes, react to what you do, and deliver the protocol's rules in their own voice. Inventory is
drag-and-drop — you pull an Augment off the wall and drop it into a bay.

Everything is authored against a fixed **1280×720** logical canvas scaled to fit
(`site/game/stage.ts`), so hotspots and sprite anchors are stable across displays.

**Terminal mode** is the alternative view — same hooks, panel-based. It serves automatically below
900px and is toggleable anywhere, because a fixed stage with pointer-drag would otherwise put a
phone user's assets out of reach.

**Art:** see [ART.md](ART.md) for the full commission brief — exact filenames, pixel dimensions and
the stall coordinates the Row backdrop must match. Every asset currently renders as a labelled
`<ArtSlot>` at its final aspect ratio, so nothing reflows when the real files land.

## Layout

```
src/tokens/         $RUN, $AUG                        (phase 1)
src/runner/         Stock//Runner ERC-721, cycles, TBA (phase 2)
src/items/          Augments, Modules, Ripperdoc       (phase 3)
script/             Foundry deploy scripts
bin/deploy.sh       deploy wrapper — sources the key from ~/.aug_run/.env
bin/run-drop.sh     Drop keeper — fires the weekly Drop on a schedule
test/               Foundry tests (345 passing)
site/               production point-and-click game on :3000 (Next.js)
ui/                 test harness on :3333 (Vite + React + wagmi/viem)
```

## Running the Drop

Firing a Drop is three on-chain steps and cannot be fewer: 333 units' weights will not fit in one
transaction, and the aggregate purchase can only happen once every weight is known. That is
operations, not gameplay — an operator at the Courier's window presses **one** button to collect,
and never sees the machinery.

```bash
bin/run-drop.sh --status   # where is the current Drop?
bin/run-drop.sh --dry      # report state, broadcast nothing
bin/run-drop.sh            # open, weigh and buy
```

Cron it once a cycle, a few minutes past the boundary:

```
5 0 * * 1  cd /path/to/aug_run && bin/run-drop.sh >> ~/.aug_run/drop.log 2>&1
```

It is safe to re-run: each step is skipped if the round is already past it, so a re-run after a
failure resumes rather than restarting. The steps are permissionless — weights are read off the
Stock//Runners themselves and never supplied, so whoever runs it chooses only *when* a Drop happens,
never who earns from it. It needs `DROP_ADDRESS` in `~/.aug_run/.env`.

The Terminal needs no equivalent. Revenue used to require someone to call `pullRewards()`; it now
sweeps itself into the streams on every stake, claim and withdraw, so there is nothing to run and
nothing to press.

## Where the rules live

The seating rules are split deliberately:

- **`StockRunner`** owns all per-unit state and enforces the *structural* invariants — bay bounds,
  the three-bay ceiling, one-change-per-bay-per-cycle, tenure reset on rebind. A buggy or replaced
  Ripperdoc cannot violate these.
- **`Ripperdoc`** owns pricing, the catalog, and the burn/reserve split.

**Binding is structural, not a check.** Seating burns the ERC-1155 and records the Augment as bay
state, so a seated Augment has no token left to move — there is no function anywhere that can
transfer it to another unit, including one the same operator owns.

## Testnet scaffolding

Both tokens carry a faucet gated behind an immutable `TESTNET` flag set in the constructor, marked
with a banner comment block in each file. The faucet never mints — the constructor parks a
pre-allocated pot in the contract's own balance and the faucet only transfers from it, so fixed
supply holds identically on testnet and mainnet. Deploying with `AUGRUN_TESTNET=false` disables the
faucet and allocates no pot. The deploy script hard-refuses `AUGRUN_TESTNET=true` on chain ID 4663.
