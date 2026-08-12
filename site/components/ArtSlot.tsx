/**
 * A reserved space for commissioned art.
 *
 * Every slot declares its intended aspect ratio and what belongs in it, so the commission has exact
 * targets and the layout does not move when the real assets land. Swap the placeholder for an
 * <Image> at the same ratio and nothing else changes.
 */
export function ArtSlot({
  label,
  ratio = '1 / 1',
  hint,
  className,
}: {
  label: string;
  ratio?: string;
  hint?: string;
  className?: string;
}) {
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
