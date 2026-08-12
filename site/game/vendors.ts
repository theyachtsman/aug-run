/**
 * The people behind the counters.
 *
 * Each vendor has a voice drawn from the spec's own characterisation — the Fence moves inventory,
 * the Ripperdoc installs hardware and doesn't ask questions, the Scrapper runs odds, the Fixer sets
 * terms. Lines are keyed by situation so a shopkeeper can react to what you're actually doing
 * rather than repeating a greeting.
 *
 * Written so that the *rules* arrive as dialogue. "One rebind per bay per cycle" is a better line
 * coming from the Ripperdoc wiping his hands than from a tooltip.
 */

export type VendorId = 'market' | 'ripperdoc' | 'terminal' | 'fixer' | 'chopshop' | 'drop';

export type Vendor = {
  id: VendorId;
  name: string; // the person
  shop: string; // the shopfront
  route: string;
  stallLabel: string; // shown when hovering the stall on the Row
  lines: Record<string, string[]>;
};

const pick = (arr: string[], seed = Math.random()) => arr[Math.floor(seed * arr.length) % arr.length];

export const VENDORS: Record<VendorId, Vendor> = {
  market: {
    id: 'market',
    name: 'The Fence',
    shop: 'Black Market',
    route: 'market',
    stallLabel: 'The Black Market — the Fence',
    lines: {
      enter: [
        "Recovered stock, all of it. Don't ask where from — you already know.",
        'Blank units on the left, trade-ins on the right. Same price either way, same as everyone.',
      ],
      mintClosed: [
        "Genesis isn't open. I can't sell you what I'm not allowed to sell yet, and neither can anyone else — it's locked in the machine, not in my ledger.",
      ],
      mintOpen: [
        'One million $RUN, factory-reset, no history. What it becomes is on you.',
      ],
      poolEmpty: [
        'Rack\'s empty. Nobody\'s selling. Come back when somebody gets desperate.',
      ],
      random: [
        "Pot luck's cheaper because you're doing me a favour — I don't have to care which one goes.",
      ],
      specific: [
        'You want that one specifically? Fine. Costs a bit more to be picky.',
      ],
      sell: [
        "I'll give you the floor and not a coin more. If your unit's worth more than the floor, we both know you shouldn't be selling it to me.",
      ],
    },
  },

  ripperdoc: {
    id: 'ripperdoc',
    name: 'The Ripperdoc',
    shop: 'Ripperdoc',
    route: 'ripperdoc',
    stallLabel: "The Ripperdoc's bay — augments and modules",
    lines: {
      enter: [
        "Sit it on the bench. I don't ask where the $AUG came from and you don't tell me.",
        'Bays open, hardware on the wall. Half of what you pay me goes up in smoke — literally. Burned.',
      ],
      hoverAugment: [
        'Tier buys weight. The ticker decides what the weight buys. Two different questions.',
      ],
      seated: [
        "That's in there for good now. It doesn't come out and go into another unit — not yours, not anyone's.",
        'Bound. Permanently. That\'s what makes the tenure mean something.',
      ],
      lockedBay: [
        "You already worked that bay this cycle. Come back after Monday — I'm not undoing my own solder.",
      ],
      swapWarning: [
        "You understand you're throwing away the tenure? It goes back to zero and climbs again from nothing.",
      ],
      tierAdvice: [
        "Got a spare bay? Fill it with a tier one first. Paying for tier three while a bay sits empty is just paying me extra for nothing.",
      ],
      calibrate: [
        "Five $AUG, once a day. Won't earn you anything by itself — just gets you to the ceiling faster. Machines need maintenance.",
      ],
      noAug: [
        "You're short. Come back with $AUG and I'll open you up.",
      ],
    },
  },

  terminal: {
    id: 'terminal',
    name: 'Terminal',
    shop: 'The Terminal',
    route: 'terminal',
    stallLabel: 'The Terminal — an unstaffed kiosk',
    lines: {
      enter: [
        'TERMINAL ONLINE. NO OPERATOR PRESENT. STAKE $AUG OR PROVIDE LIQUIDITY.',
        'REVENUE SHARE: 20% STAKERS / 20% LIQUIDITY. PAID CONTINUOUSLY.',
      ],
      staked: ['POSITION RECORDED. ACCRUAL BEGINS THIS SECOND.'],
      queued: [
        'REVENUE HELD: NO STAKE PRESENT. FUNDS WILL NOT BE RELEASED INTO AN EMPTY POOL.',
      ],
      claim: ['TRANSFER COMPLETE. POSITION UNCHANGED.'],
    },
  },

  fixer: {
    id: 'fixer',
    name: 'The Fixer',
    shop: 'The Fixer',
    route: 'fixer',
    stallLabel: "The Fixer's booth — loans against collateral",
    lines: {
      enter: [
        'Sit. You want money against something you own. I want to know how long for.',
        "I lend from the market's own pool. Keeps everything honest and keeps the supply fixed.",
      ],
      quote: [
        'Half of what the floor says it\'s worth. Rate\'s paid up front, in ETH, and it moves with the market\'s own fee.',
      ],
      ltvWarning: [
        "You're drifting. Seventy percent and you're Iced — I take the keys, though you can still buy them back until I move it on.",
      ],
      augmentLoan: [
        'An Augment that\'s never been seated is still an asset. Seated, it\'s part of the machine and no good to me.',
      ],
      repaid: ["Clean. Interest goes in the furnace — I don't keep it."],
    },
  },

  chopshop: {
    id: 'chopshop',
    name: 'The Scrapper',
    shop: 'Chop Shop',
    route: 'chopshop',
    stallLabel: "The Scrapper's table — roll for it",
    lines: {
      enter: [
        'Table rotates every day. What you see is what there is.',
        "Back your item heavy and it's hard to win. Back it light and everyone fancies their chances. Your call.",
      ],
      listed: ["On the table. Let's see who's feeling lucky."],
      rolled: [
        "Committed. I can't see the result yet either — it's riding on a block that hasn't happened.",
      ],
      won: ["Well. Take the item, take the cash, or take it in $AUG. Don't take all day."],
      lost: ["House keeps it. Better luck when the table turns over."],
    },
  },

  drop: {
    id: 'drop',
    name: 'The Courier',
    shop: 'The Drop',
    route: 'drop',
    stallLabel: 'The Courier — collect your package',
    lines: {
      enter: [
        "I don't deliver. I hold. You collect.",
        "Everything's already bought — one purchase per ticker, split by weight. Your share is behind the counter.",
      ],
      nothing: ["Nothing for that unit this cycle. Seated too late, or seated nothing at all."],
      collect: ["Goes into the unit's own wallet, not yours. That's the point of the thing."],
      expiring: [
        "Window shuts an hour before the next one. After that I sell it and it funds a buyback. Don't make me.",
      ],
    },
  },
};

export function line(v: VendorId, key: string, seed?: number): string {
  const set = VENDORS[v].lines[key] ?? VENDORS[v].lines.enter;
  return pick(set, seed ?? 0.42);
}

export const VENDOR_ORDER: VendorId[] = [
  'market',
  'ripperdoc',
  'terminal',
  'fixer',
  'chopshop',
  'drop',
];
