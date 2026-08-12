'use client';

import type {ReactNode} from 'react';

/**
 * The centre display, for shops whose subject is not a Stock//Runner.
 *
 * Deliberately reuses `.preview` so the reserved centre region is pixel-identical everywhere — the
 * art brief commits one rectangle of every interior to this panel, and a shop that drew its own box
 * a few pixels off would show it the moment the painted backdrops land.
 */
export function CentrePanel({
  title,
  sub,
  children,
}: {
  title: string;
  sub?: string;
  children: ReactNode;
}) {
  return (
    <div className="preview">
      <div className="centre-head">
        <div className="centre-title mono">{title}</div>
        {sub && <div className="centre-sub faint">{sub}</div>}
      </div>
      <div className="centre-body">{children}</div>
    </div>
  );
}

/** A big readout — the number the shop is actually about. */
export function BigStat({
  value,
  unit,
  label,
  tone,
}: {
  value: string;
  unit?: string;
  label: string;
  tone?: 'red' | 'lime' | 'sodium';
}) {
  return (
    <div className="bigstat">
      <div className={`bigstat-v ${tone ?? ''}`}>
        {value}
        {unit && <span className="bigstat-u">{unit}</span>}
      </div>
      <div className="bigstat-l">{label}</div>
    </div>
  );
}

/** Compact key/value line for the centre panel. */
export function Line({k, v, tone}: {k: string; v: string; tone?: 'red' | 'lime' | 'sodium'}) {
  return (
    <div className="cline">
      <span className="cline-k">{k}</span>
      <span className={`cline-v ${tone ?? ''}`}>{v}</span>
    </div>
  );
}
