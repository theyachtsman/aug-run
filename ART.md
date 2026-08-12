# AUG//RUN — art commission brief

Everything renders inside a fixed **1280 × 720** logical canvas that scales to fit the display.
Deliver at **2× (2560 × 1440)** so it stays sharp on high-DPI screens.

**Style:** painted / digital illustration. Not pixel art. Neon cyberpunk — **true blacks**, light
coming from signage and sodium lamps rather than ambient fill. **Red (`#ff2740`) is AUG//RUN's own
colour** and should appear as the dominant signage hue; cyan (`#34e8ff`) is the street's secondary.
Grimy industrial: corrugated shutters, service gantries, converted loading bays, wet concrete.

Reference tone: the strip should feel *lived in and salvaged*, not glossy. This is where recovered
hardware changes hands.

---

## 1. Runners Row backdrop — the hub

| | |
|---|---|
| File | `row-backdrop.png` |
| Size | 2560 × 1440 (renders at 1280 × 720) |
| Format | PNG or high-quality JPG, no alpha |

One continuous industrial strip showing **all six stalls side by side**, viewed straight on like a
90s adventure game street scene. The player clicks a stall to enter it.

**Critical — stalls must sit inside these regions.** Coordinates are in 1280 × 720 logical pixels;
double them for the 2× file. A stall's frontage should visually occupy its box so the clickable area
matches what the eye expects.

| Stall | x | y | w | h | 2× region |
|---|---|---|---|---|---|
| Black Market (the Fence) | 40 | 150 | 210 | 380 | 80,300 → 500,1060 |
| Ripperdoc | 258 | 170 | 200 | 360 | 516,340 → 916,1060 |
| The Terminal (kiosk) | 466 | 250 | 130 | 270 | 932,500 → 1192,1040 |
| The Fixer | 604 | 165 | 205 | 365 | 1208,330 → 1618,1060 |
| Chop Shop (the Scrapper) | 817 | 155 | 210 | 375 | 1634,310 → 2054,1060 |
| The Drop (the Courier) | 1035 | 180 | 205 | 350 | 2070,360 → 2480,1060 |

Notes:
- Keep the **top-left ~420 × 130** region visually quiet — the AUG//RUN logo overlays there.
- The **bottom ~150px** is where the dialogue box sits when a vendor speaks. Nothing critical there.
- The Terminal is an unstaffed **wall-mounted kiosk**, narrower than the others and set back — it
  should read as a machine bolted to the wall, not a shopfront.
- Each stall wants distinct signage so it is identifiable at a glance without reading a label.

---

## 2. Shop interiors — six backdrops

| | |
|---|---|
| Files | `interior-market.png`, `interior-ripperdoc.png`, `interior-terminal.png`, `interior-fixer.png`, `interior-chopshop.png`, `interior-drop.png` |
| Size | 2560 × 1440 each |
| Format | PNG or JPG, no alpha |

The interior behind the counter. The vendor is a **separate cutout layered on top**, so do not paint
them into the background.

Four regions of every interior are covered by UI and must stay visually quiet. These are measured
from the shipped stylesheet, so they are exact:

| Region | Logical px | What sits there |
|---|---|---|
| Left | x 60–360, standing on a floor line at y 552 | the vendor cutout |
| **Centre** | **x 386–722, y 68–544** | **the centre display panel** |
| Right | x 754–1254, y 26–526 | the shop menu |
| Bottom | x 24–1256, y 550–700 | the dialogue box |

**Every one of the six interiors uses the centre panel** — it is the focal object of each shop, so
each interior wants an obvious empty space in the middle of frame for something to be stood up and
looked at:

| Interior | What occupies the centre | So the backdrop wants |
|---|---|---|
| Black Market | the selected unit, full body | a lit inspection plate or display alcove |
| Ripperdoc | the unit on the bench, full body | a clamp rig or gantry |
| The Terminal | a revenue readout | a recessed screen bezel or cable run |
| The Fixer | the unit you are pledging | a spot on the customer's side of the desk |
| Chop Shop | an odds ring | a hard-lit patch of table |
| The Drop | a parcel manifest | an empty shelf slot at the collection window |

The two that carry the most weight are the **Black Market and the Ripperdoc**, where a Stock//Runner
stands nearly 340px wide while the operator decides what to do with it.

| Interior | Character |
|---|---|
| Black Market | Racks of dormant units, inventory tags, a counter worn smooth |
| Ripperdoc | A workbench with a unit clamped open, tools, hardware on pegboard, sharps bin |
| The Terminal | No room at all — a lit wall panel, cabling, a slot. Cold, unattended |
| The Fixer | A booth. Ledgers, a safe, one chair on your side of the desk |
| Chop Shop | A table under a hard lamp, parts in trays, odds chalked on the wall |
| The Drop | A parcel office. Shelves of sealed packages, a collection window |

---

## 3. Vendor cutouts — five characters

| | |
|---|---|
| Files | `vendor-market.png`, `vendor-ripperdoc.png`, `vendor-fixer.png`, `vendor-chopshop.png`, `vendor-drop.png` |
| Size | **600 × 1000** (3:5, renders 300 × 500 logical) |
| Format | **PNG with alpha** — cut out, no background |

The slot is anchored so the figure stands from **y 52 to y 552** — feet on the floor line, head near
the top of frame. The dialogue box crosses the last two pixels of the feet, which is correct: it sits
in front of the scene.

Full-body, standing behind the counter, facing the viewer. Flat cutout layered over the interior —
they do not need to be lit to match perfectly, a slight separation is period-correct.

The Terminal has **no vendor** — it is deliberately unstaffed. That absence is a design point in the
spec, so please do not add an attendant.

| Vendor | Who they are |
|---|---|
| **The Fence** | Moves inventory. Doesn't care what it is, cares what it goes for |
| **The Ripperdoc** | Installs hardware, doesn't ask questions. Hands that work |
| **The Fixer** | Sets terms. The one who is comfortable while you decide |
| **The Scrapper** | Runs the odds. Enjoys this more than you do |
| **The Courier** | Holds packages. Does not deliver them |

---

## 4. Portraits — dialogue box

| | |
|---|---|
| Files | `portrait-<vendor>.png` |
| Size | 416 × 416 (renders 104 × 104) |
| Format | PNG, alpha optional |

Head and shoulders, framed tight, readable at 104px. Used in the dialogue box while they speak.

---

## 5. Model line renders — the 333

| | |
|---|---|
| Files | `model-00.png` … `model-10.png` (11 lines) |
| Size | 900 × 1200 (3:4, renders ~300 × 400) |
| Format | PNG with alpha |

**Siblings, not a hierarchy.** Vary silhouette, posture and wear — never quality. No model may read
as rarer or better than another; equal counts keep supply rarity off the table and sibling design
keeps aesthetic rarity off it too. If one looks like the "good" one, the economy breaks.

Working names (changeable, they live in one array): MK-I, MK-II, DRAYTON, HALSEY, VOSS, KESTREL,
ORRIN, SABLE, MERIDIAN, CASTELL, NORTHWIND.

These are androids that were **physically repossessed off the street, then wiped back to factory
default** — not new, just clean. Stripped of corporate branding.

**These renders carry the most weight in the product.** They fill the centre preview panel at the
Black Market and the Ripperdoc, where a unit stands nearly 340px wide while the operator decides
whether to buy, sell, or open it up. Frame them full-body, straight on, standing — they are being
inspected on a bench, not posed for a poster.

---

## 6. Augment badges — 12+

| | |
|---|---|
| Files | `augment-<ticker>.png` |
| Size | 256 × 256 (renders 76 × 76 in inventory) |
| Format | PNG with alpha |

Augments display as **labelled badges, not composited artwork** — an installed optic reads as a
badge tied to its ticker, with the hardware implied rather than drawn onto the android. This is what
frees every model to be its own piece of art.

Three tiers, colour-keyed in the UI: T1 cyan, T2 violet, T3 amber. The badge should read at a glance
as hardware, with room for the ticker text the UI overlays.

Launch tickers are **placeholders** pending what is liquid on Robinhood Chain — design the badge
system, not twelve specific logos.

Each Augment carries a **hardware name and a body slot** alongside its ticker, so the badge should
read as a physical component. Current naming (see `site/game/augmentNames.ts`):

| Ticker | Slot | Hardware |
|---|---|---|
| SPY | OPTIC | Wide-Spectrum Optic |
| JNJ | VISCERAL | Immune Regulator |
| BRKB | CORTEX | Ledger Cortex |
| TSLA | ADRENAL | Adrenal Spike |
| QQQ | CORTEX | Neural Lattice |
| AAPL | DERMAL | Haptic Dermis |
| KO | CARDIAC | Hydraulic Pump |
| COIN | SPINAL | Volatility Governor |
| NVDA | OPTIC | Optic Nerve MK-III |
| MSFT | CORTEX | Kernel Core |
| AMD | CORTEX | Parallel Cortex |
| GLD | SKELETAL | Ballast Plate |

Badges could be drawn **per slot type** rather than per ticker — eight slot icons (OPTIC, CORTEX,
DERMAL, SPINAL, CARDIAC, ADRENAL, SKELETAL, VISCERAL) would cover the whole catalog and every future
listing, with the UI overlaying the ticker text. That is far less work than one badge per asset and
survives the catalog expanding.

---

## Delivery

Drop files into `site/public/art/` using the filenames above. Every slot is currently a labelled
placeholder at the exact final aspect ratio, so nothing reflows when the real assets arrive — the
`<ArtSlot>` component is swapped for an `<Image>` at the same ratio and the layout is unchanged.
