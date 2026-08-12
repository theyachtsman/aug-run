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

/** Where each stall sits on the Runners Row backdrop, in logical pixels. */
export const ROW_HOTSPOTS: Record<string, Rect> = {
  market: {x: 40, y: 150, w: 210, h: 380},
  ripperdoc: {x: 258, y: 170, w: 200, h: 360},
  terminal: {x: 466, y: 250, w: 130, h: 270},
  fixer: {x: 604, y: 165, w: 205, h: 365},
  chopshop: {x: 817, y: 155, w: 210, h: 375},
  drop: {x: 1035, y: 180, w: 205, h: 350},
};

/** Convert a viewport point to logical stage coordinates. */
export function toStage(clientX: number, clientY: number, el: HTMLElement) {
  const r = el.getBoundingClientRect();
  const scale = r.width / STAGE_W;
  return {x: (clientX - r.left) / scale, y: (clientY - r.top) / scale};
}
