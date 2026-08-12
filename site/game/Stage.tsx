'use client';

import {useEffect, useRef, useState, type ReactNode} from 'react';
import {STAGE_W, STAGE_H} from './stage';

/**
 * Scales the fixed logical canvas to fit the viewport, preserving aspect and letterboxing the
 * remainder. Uses a CSS transform rather than resizing anything, so children can be positioned in
 * absolute logical pixels and never need to know the display size.
 */
export function Stage({children}: {children: ReactNode}) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const fit = () => {
      const el = wrapRef.current;
      if (!el) return;
      const {width, height} = el.getBoundingClientRect();
      setScale(Math.min(width / STAGE_W, height / STAGE_H));
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);

  return (
    <div ref={wrapRef} className="stage-wrap">
      <div
        className="stage"
        style={{
          width: STAGE_W,
          height: STAGE_H,
          transform: `scale(${scale})`,
        }}
        data-stage
      >
        {children}
      </div>
    </div>
  );
}
