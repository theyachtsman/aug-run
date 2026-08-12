# Drop artwork here

Every file below is optional and independent. A slot with no file shows a labelled placeholder at
the exact final aspect ratio, so art can arrive one piece at a time and nothing reflows when it
does. No code change is needed per asset — just the filename.

Full specification, including the UI-safe regions each backdrop must keep quiet, is in `ART.md` at
the repo root.

| File | Size | Notes |
|---|---|---|
| `logo.png` | wide, transparent or black | The AUG//RUN mark. Used in the HUD at 30px tall and on the Row at 82px, so it must stay legible small. |
| `row-backdrop.png` | 2560×1440 | Runners Row, all six stalls. Stall positions must match `ROW_HOTSPOTS` in `site/game/stage.ts` — hold **H** on the Row to see the boxes drawn over the art. |
| `interior-market.png` | 2560×1440 | Black Market interior |
| `interior-ripperdoc.png` | 2560×1440 | Ripperdoc interior |
| `interior-terminal.png` | 2560×1440 | Terminal — a wall kiosk, no room |
| `interior-fixer.png` | 2560×1440 | Fixer's booth |
| `interior-chopshop.png` | 2560×1440 | Chop Shop interior |
| `interior-drop.png` | 2560×1440 | The Drop's parcel office |
| `vendor-market.png` | 600×1000, alpha | The Fence, cut out |
| `vendor-ripperdoc.png` | 600×1000, alpha | The Ripperdoc, cut out |
| `vendor-fixer.png` | 600×1000, alpha | The Fixer, cut out |
| `vendor-chopshop.png` | 600×1000, alpha | The Scrapper, cut out |
| `vendor-drop.png` | 600×1000, alpha | The Courier, cut out |

There is deliberately **no `vendor-terminal.png`** — the Terminal is unstaffed by design, and the
scene suppresses the cutout slot entirely rather than leaving a gap.

Interiors and cutouts are separate files on purpose: the vendor is layered over the room, so a
vendor painted into a backdrop cannot be composited and will not line up with the dialogue portrait.
