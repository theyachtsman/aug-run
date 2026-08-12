'use client';

import {useState} from 'react';

/**
 * A reserved space for commissioned art.
 *
 * Every slot declares its intended aspect ratio and what belongs in it, so the commission has exact
 * targets and the layout does not move when the real assets land.
 *
 * Pass `src` and the slot shows the artwork; if that file is not there yet the slot falls back to
 * its labelled placeholder rather than a broken image. That means art can be dropped into
 * site/public/art/ one file at a time, in any order, with no code change per asset — which is what
 * you want when a commission arrives in pieces.
 */
export function ArtSlot({
  label,
  ratio = '1 / 1',
  hint,
  className,
  src,
  fit = 'cover',
}: {
  label: string;
  ratio?: string;
  hint?: string;
  className?: string;
  /** Path under /public, e.g. "/art/row-backdrop.png". Falls back to the placeholder if missing. */
  src?: string;
  fit?: 'cover' | 'contain';
}) {
  const [failed, setFailed] = useState(false);

  if (src && !failed) {
    return (
      <img
        src={src}
        alt={label}
        className={`art-img ${className ?? ''}`}
        style={{aspectRatio: ratio, objectFit: fit}}
        onError={() => setFailed(true)}
      />
    );
  }

  return (
    <div className={`art ${className ?? ''}`} style={{aspectRatio: ratio}}>
      <div>
        <div style={{color: 'var(--dim)'}}>{label}</div>
        {hint && <div style={{marginTop: 4, opacity: 0.7}}>{hint}</div>}
        <div style={{marginTop: 6, opacity: 0.5}}>{ratio.replace(' ', '')}</div>
      </div>
    </div>
  );
}

/** The 11 model lines. Sibling designs, not a hierarchy — no model is rarer or better. */
export const MODEL_NAMES = [
  'MK-I',
  'MK-II',
  'DRAYTON',
  'HALSEY',
  'VOSS',
  'KESTREL',
  'ORRIN',
  'SABLE',
  'MERIDIAN',
  'CASTELL',
  'NORTHWIND',
] as const;

export function modelName(i?: number) {
  return i === undefined ? '—' : (MODEL_NAMES[i] ?? `LINE-${i}`);
}
