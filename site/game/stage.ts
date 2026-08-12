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
 * Measured against the current backdrop: each box spans its sign band down to the floor, and stops
 * at the pillar between it and its neighbour, so the clickable area matches the shopfront a player
 * is actually aiming at. The stalls are not equal widths — the Terminal is a narrow wall kiosk and
 * the Fence has the widest frontage — and forcing them into a uniform grid would put the Terminal's
 * hotspot over its neighbours' doorways.
 *
 * **Retuning:** press `H` on the Row to outline every box over the art. Adjust here and only here;
 * nothing else hard-codes a stall position.
 */
export const ROW_HOTSPOTS: Record<string, Rect> = {
  market: {x: 34, y: 165, w: 222, h: 385},
  ripperdoc: {x: 284, y: 165, w: 142, h: 385},
  terminal: {x: 428, y: 165, w: 74, h: 385},
  fixer: {x: 505, y: 165, w: 240, h: 385},
  chopshop: {x: 749, y: 165, w: 238, h: 385},
  drop: {x: 989, y: 165, w: 202, h: 385},
};

/** Convert a viewport point to logical stage coordinates. */
export function toStage(clientX: number, clientY: number, el: HTMLElement) {
  const r = el.getBoundingClientRect();
  const scale = r.width / STAGE_W;
  return {x: (clientX - r.left) / scale, y: (clientY - r.top) / scale};
}
