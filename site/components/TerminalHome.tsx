import Link from 'next/link';
import {MintStatus} from './MintStatus';
import {VENDORS, VENDOR_ORDER} from '@/game/vendors';

/**
 * Terminal mode — the same protocol without the scene.
 *
 * Serves automatically on narrow screens and stays available by choice anywhere. Not a marketing
 * page: a phone user must be able to reach their own assets, and a fixed 1280×720 stage with
 * pointer-drag inventory cannot give them that.
 */
export function TerminalHome() {
  return (
    <main className="wrap">
      <section style={{marginBottom: 24}}>
        <div className="logo" style={{fontSize: 30}}>
          AUG<span className="slash">//</span>RUN
        </div>
        <div
          className="mono"
          style={{fontSize: 11, letterSpacing: '0.22em', color: 'var(--dim)', marginTop: 4}}
        >
          TERMINAL MODE · RUNNERS ROW
        </div>
        <p className="dim" style={{maxWidth: '62ch', marginTop: 12}}>
          333 recovered corporate units, each with its own onchain wallet. Mint a blank Stock//Runner,
          augment it, and let it work the market. What separates two units is entirely what their
          operators did.
        </p>
      </section>

      <MintStatus />

      <section style={{marginTop: 24}}>
        <h3 style={{marginBottom: 10}}>The Row</h3>
        <div className="grid g3">
          {VENDOR_ORDER.map((id) => {
            const v = VENDORS[id];
            return (
              <Link key={id} href={`/${v.route}`} className="panel" style={{display: 'block'}}>
                <div
                  className="mono"
                  style={{fontSize: 10, letterSpacing: '0.16em', color: 'var(--red)'}}
                >
                  {v.name}
                </div>
                <div style={{fontSize: 16, fontWeight: 600, letterSpacing: '0.04em', margin: '4px 0 6px'}}>
                  {v.shop}
                </div>
                <div className="dim" style={{fontSize: 12}}>
                  {v.stallLabel}
                </div>
              </Link>
            );
          })}
        </div>
      </section>

      <section className="grid g2" style={{marginTop: 24}}>
        <div className="panel">
          <h3>What separates two units</h3>
          <p className="dim" style={{fontSize: 13}}>
            Every unit mints at identical rarity. No model is scarcer and none carries a mechanical
            advantage. Capacity, tier and tenure are the only three things that move earnings — and
            tenure is only earned by leaving something alone.
          </p>
          <div className="row" style={{marginTop: 10}}>
            <span className="tag t1">T1 · 1.0x</span>
            <span className="tag t2">T2 · 1.25x</span>
            <span className="tag t3">T3 · 1.5x</span>
            <span className="tag on">tenure to 1.5x</span>
          </div>
        </div>
        <div className="panel">
          <h3>The machine remembers</h3>
          <p className="dim" style={{fontSize: 13}}>
            Tenure survives a sale — the buyer inherits earning power, not just a history log. But
            rebinding resets it, even for a new owner. A tenured unit is worth what it is worth{' '}
            <em>as configured</em>.
          </p>
        </div>
      </section>
    </main>
  );
}
