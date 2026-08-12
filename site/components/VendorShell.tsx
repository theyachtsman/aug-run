import Link from 'next/link';
import type {ReactNode} from 'react';

/** Consistent frame for every shopfront on the Row: who runs it, what it is, and the way back. */
export function VendorShell({
  vendor,
  name,
  blurb,
  children,
}: {
  vendor: string;
  name: string;
  blurb: string;
  children: ReactNode;
}) {
  return (
    <main className="wrap">
      <Link href="/" className="btn sm ghost">
        ← Runners Row
      </Link>

      <header style={{marginTop: 18, marginBottom: 22}}>
        <div className="mono" style={{fontSize: 11, letterSpacing: '0.16em', color: 'var(--sodium)'}}>
          {vendor}
        </div>
        <h1 style={{marginTop: 4}}>{name}</h1>
        <p className="dim" style={{maxWidth: '64ch', marginTop: 10, marginBottom: 0}}>
          {blurb}
        </p>
      </header>

      {children}
    </main>
  );
}

/** A labelled readout. The site is full of these, so it's worth one component. */
export function Stat({
  k,
  v,
  accent,
  sub,
}: {
  k: string;
  v: ReactNode;
  accent?: boolean;
  sub?: string;
}) {
  return (
    <div className="between" style={{padding: '4px 0', alignItems: 'baseline'}}>
      <div>
        <span className="dim" style={{fontSize: 12}}>
          {k}
        </span>
        {sub && (
          <div className="faint" style={{fontSize: 11}}>
            {sub}
          </div>
        )}
      </div>
      <span className="mono" style={{color: accent ? 'var(--chrome)' : undefined, textAlign: 'right'}}>
        {v}
      </span>
    </div>
  );
}

/** Explains a rule in the operator's language, next to the control it governs. */
export function Rule({children}: {children: ReactNode}) {
  return (
    <p className="faint" style={{fontSize: 11.5, marginTop: 10, marginBottom: 0, maxWidth: '68ch'}}>
      {children}
    </p>
  );
}

export function NotConnected() {
  return (
    <div className="notice">
      <strong style={{color: 'var(--sodium)'}}>Not connected.</strong>{' '}
      <span className="dim">Connect a wallet from the HUD to trade here.</span>
    </div>
  );
}
