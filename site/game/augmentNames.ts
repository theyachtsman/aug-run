/**
 * Hardware names for the Augment catalog.
 *
 * The spec describes Augments as badges where "an installed optic reads as a labelled Optic badge
 * tied to its ticker, with the hardware implied rather than drawn onto the android." So each
 * Augment is two things at once: a piece of chrome bolted into a bay, and the real-world asset it
 * tracks. The ticker is the truth; the hardware name is what the street calls it.
 *
 * Names are chosen so the *character* of the asset survives the translation — a high-beta name gets
 * adrenal hardware, a defensive one gets immune hardware, a store of value gets ballast. Tier is
 * never implied by the name, because tier and risk are deliberately independent axes: a cautious
 * operator must be able to max tier while holding steady names.
 *
 * Tickers are placeholders pending what is liquid on Robinhood Chain, so this maps by symbol with a
 * generated fallback — adding an Augment later never requires touching this file.
 */

export type Hardware = {
  /** What the street calls it. */
  name: string;
  /** Where it goes. Used as the badge's category label. */
  slot: string;
  /** One line the Ripperdoc might say about it. */
  flavour: string;
};

const CATALOG: Record<string, Hardware> = {
  // ---- tier 1 · broad index · defensive · value · one high-beta
  SPY: {
    name: 'Wide-Spectrum Optic',
    slot: 'OPTIC',
    flavour: 'Sees everything at once. Nothing sharply.',
  },
  JNJ: {
    name: 'Immune Regulator',
    slot: 'VISCERAL',
    flavour: "Boring hardware. Boring hardware doesn't fail.",
  },
  BRKB: {
    name: 'Ledger Cortex',
    slot: 'CORTEX',
    flavour: 'Remembers what things are worth. Waits.',
  },
  TSLA: {
    name: 'Adrenal Spike',
    slot: 'ADRENAL',
    flavour: "Runs hot. You'll feel every move it makes.",
  },

  // ---- tier 2 · broad tech · mega-cap · defensive · one volatile
  QQQ: {
    name: 'Neural Lattice',
    slot: 'CORTEX',
    flavour: 'A whole sector wired into one mesh.',
  },
  AAPL: {
    name: 'Haptic Dermis',
    slot: 'DERMAL',
    flavour: 'Everyone has one. That is rather the point.',
  },
  KO: {
    name: 'Hydraulic Pump',
    slot: 'CARDIAC',
    flavour: "Been in service a century. Still pumping.",
  },
  COIN: {
    name: 'Volatility Governor',
    slot: 'SPINAL',
    flavour: "Governor's a joke. Thing has no governor at all.",
  },

  // ---- tier 3 · mega-cap momentum · stable mega · volatile · one alternative
  NVDA: {
    name: 'Optic Nerve MK-III',
    slot: 'OPTIC',
    flavour: 'Best glass on the Row. Priced like it, too.',
  },
  MSFT: {
    name: 'Kernel Core',
    slot: 'CORTEX',
    flavour: 'Runs underneath everything else you own.',
  },
  AMD: {
    name: 'Parallel Cortex',
    slot: 'CORTEX',
    flavour: 'Thinks in threads. Occasionally overheats.',
  },
  GLD: {
    name: 'Ballast Plate',
    slot: 'SKELETAL',
    flavour: "Heavy. Doesn't do much. That's the job.",
  },
};

const SLOTS = ['OPTIC', 'CORTEX', 'DERMAL', 'SPINAL', 'CARDIAC', 'ADRENAL', 'SKELETAL', 'VISCERAL'];
const FALLBACK = ['Interface Module', 'Signal Relay', 'Grafted Node', 'Ported Array'];

/** Never throws on an unknown ticker — the catalog is designed to expand without a code change. */
export function hardware(ticker: string): Hardware {
  const hit = CATALOG[ticker?.toUpperCase?.() ?? ''];
  if (hit) return hit;

  // Deterministic so a new listing gets a stable name rather than one that shuffles per render.
  let h = 0;
  for (const c of ticker ?? '') h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return {
    name: `${ticker} ${FALLBACK[h % FALLBACK.length]}`,
    slot: SLOTS[h % SLOTS.length],
    flavour: 'New stock. Came in this week.',
  };
}
