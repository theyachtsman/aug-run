'use client';

import Link from 'next/link';
import {VENDORS, type VendorId} from '../vendors';

/**
 * Placeholder counter for the vendors whose game menus are not built yet.
 *
 * These four already work fully in terminal mode against the live contracts — what is missing is
 * the game presentation, not the functionality. Saying that outright and linking straight through
 * beats a shopfront that looks finished and does nothing.
 */
export function SimpleShopScene({id, onSay}: {id: VendorId; onSay: (s: string) => void}) {
  const v = VENDORS[id];

  return (
    <div className="shop-menu">
      <h3 style={{marginBottom: 10}}>{v.shop}</h3>

      <p className="dim" style={{fontSize: 12.5, marginTop: 0}}>
        {v.name} has the counter open, but this menu is still being built. Everything here works now
        in terminal mode against the live contracts — it is the presentation that is unfinished, not
        the mechanics.
      </p>

      <Link href={`/${v.route}`} className="btn primary" style={{display: 'inline-block', marginTop: 8}}>
        open in terminal mode
      </Link>

      <p className="faint" style={{fontSize: 11, marginTop: 12, marginBottom: 0}}>
        Press <strong>Esc</strong> to step back out onto the Row.
      </p>
    </div>
  );
}
