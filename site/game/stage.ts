/**
 * The stage.
 *
 * Everything is authored against a fixed 1280×720 logical canvas and scaled to fit the viewport,
 * the way a game does — not reflowed like a web page. Hotspot rectangles, sprite anchors and the
 * dialogue box are all written in logical pixels, so a position that looks right at authoring time
 * looks right on every display.
 */
export const STAGE_W = 1280;
export const STAGE_H = 720;

/** Logical pixels per dissolve block. 40 × 23 blocks — chunky enough to read as a 90s dissolve. */
export const DISSOLVE_BLOCK = 32;

export type Rect = {x: number; y: number; w: number; h: number};

/**
 * Where each stall sits on the Runners Row backdrop, in logical pixels.
 *
 * Measured off the rendered backdrop rather than estimated from the source art — the stage is
 * letterboxed and scaled, so eyeballing positions from the raw image is how the first pass ended up
 * over 100px out on the Terminal.
 *
 * Each box runs from the sign band (y 200) to the floor (y 600) and spans its bay plus the pillar
 * signage that belongs to it — "BETTER THAN FACTORY DEFAULT" is the Ripperdoc's pitch, "DISCRETION
 * IS DEADLY" is the Fixer's, "WE TAKE ANYTHING APART" is the Scrapper's — because a player who
 * clicks a shop's own sign expects to walk into that shop.
 *
 * The stalls are deliberately unequal. The Terminal is a narrow wall kiosk at 110 wide against the
 * Ripperdoc's 252; a uniform grid would put its box over its neighbours' doorways.
 *
 * **Retuning:** hold `H` on the Row to outline every box over the art. Adjust here and only here;
 * nothing else hard-codes a stall position.
 */
export const ROW_HOTSPOTS: Record<string, Rect> = {
  market: {x: 30, y: 200, w: 232, h: 400},
  ripperdoc: {x: 268, y: 200, w: 252, h: 400},
  terminal: {x: 530, y: 200, w: 110, h: 400},
  fixer: {x: 648, y: 200, w: 251, h: 400},
  chopshop: {x: 903, y: 200, w: 200, h: 400},
  drop: {x: 1108, y: 200, w: 172, h: 400},
};

/** Convert a viewport point to logical stage coordinates. */
export function toStage(clientX: number, clientY: number, el: HTMLElement) {
  const r = el.getBoundingClientRect();
  const scale = r.width / STAGE_W;
  return {x: (clientX - r.left) / scale, y: (clientY - r.top) / scale};
}
