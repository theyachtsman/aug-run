'use client';

import {useMemo} from 'react';
import {STAGE_W, STAGE_H, DISSOLVE_BLOCK} from './stage';

/**
 * The 90s dissolve wipe.
 *
 * A grid of blocks fades in over the outgoing scene in pseudo-random order, the scene swaps behind
 * it, then the blocks fade back out. Chunky and staggered rather than a smooth crossfade, because a
 * smooth crossfade reads as a modern web transition and this is meant to read as VGA.
 *
 * The order is seeded and stable, so a dissolve looks the same every time rather than shimmering
 * differently on each navigation.
 */
export function Dissolve({phase}: {phase: 'in' | 'out' | 'idle'}) {
  const cols = Math.ceil(STAGE_W / DISSOLVE_BLOCK);
  const rows = Math.ceil(STAGE_H / DISSOLVE_BLOCK);

  const order = useMemo(() => {
    const n = cols * rows;
    const idx = Array.from({length: n}, (_, i) => i);
    // Deterministic shuffle — a fixed seed keeps the pattern identical across transitions.
    let seed = 0x9e3779b9;
    for (let i = n - 1; i > 0; i--) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const j = seed % (i + 1);
      [idx[i], idx[j]] = [idx[j], idx[i]];
    }
    const delays = new Array<number>(n);
    idx.forEach((cell, rank) => {
      delays[cell] = (rank / n) * 260; // ms — whole sweep lands in ~260ms
    });
    return delays;
  }, [cols, rows]);

  if (phase === 'idle') return null;

  return (
    <div className="dissolve" aria-hidden>
      {order.map((delay, i) => (
        <span
          key={i}
          style={{
            left: (i % cols) * DISSOLVE_BLOCK,
            top: Math.floor(i / cols) * DISSOLVE_BLOCK,
            width: DISSOLVE_BLOCK,
            height: DISSOLVE_BLOCK,
            opacity: phase === 'in' ? 1 : 0,
            transitionDelay: `${phase === 'in' ? delay : 260 - delay}ms`,
          }}
        />
      ))}
    </div>
  );
}
