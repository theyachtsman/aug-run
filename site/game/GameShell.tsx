'use client';

import {useCallback, useEffect, useState} from 'react';
import {Stage} from './Stage';
import {Dissolve} from './Dissolve';
import {Dialogue} from './Dialogue';
import {DragProvider} from './dnd';
import {ROW_HOTSPOTS, type Rect} from './stage';
import {VENDORS, VENDOR_ORDER, line, type VendorId} from './vendors';
import {ArtSlot} from '@/components/ArtSlot';
import {MarketScene} from './scenes/MarketScene';
import {RipperdocScene} from './scenes/RipperdocScene';
import {TerminalScene} from './scenes/TerminalScene';
import {FixerScene} from './scenes/FixerScene';
import {ChopShopScene} from './scenes/ChopShopScene';
import {DropScene} from './scenes/DropScene';

type SceneId = 'row' | VendorId;

/**
 * The point-and-click shell.
 *
 * One scene at a time. Leaving a scene runs a dissolve to black, swaps behind it, then dissolves
 * back — so the transition covers the swap rather than the swap being visible under a crossfade.
 *
 * Dialogue is owned here rather than by each scene, because the vendor should be able to react to
 * things that happen inside the shop ("that's in there for good now") without every scene
 * reimplementing a dialogue queue.
 */
export function GameShell() {
  const [scene, setScene] = useState<SceneId>('row');
  const [phase, setPhase] = useState<'idle' | 'in' | 'out'>('idle');
  const [say, setSay] = useState<string>('');

  const go = useCallback((next: SceneId) => {
    setPhase('in');
    window.setTimeout(() => {
      setScene(next);
      setSay(next === 'row' ? '' : line(next as VendorId, 'enter'));
      setPhase('out');
      window.setTimeout(() => setPhase('idle'), 420);
    }, 300);
  }, []);

  // Escape always walks back out to the Row — a point-and-click needs one reliable way out.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && scene !== 'row') go('row');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [scene, go]);

  const vendor = scene === 'row' ? null : VENDORS[scene as VendorId];

  return (
    <DragProvider>
      <Stage>
        {scene === 'row' ? (
          <RowScene onEnter={go} />
        ) : (
          <ShopScene id={scene as VendorId} onBack={() => go('row')} onSay={setSay} />
        )}

        {vendor && say && (
          <Dialogue speaker={vendor.name} line={say} machine={scene === 'terminal'} />
        )}

        <Dissolve phase={phase} />
      </Stage>
    </DragProvider>
  );
}

/* ------------------------------------------------------------------ ROW */

function RowScene({onEnter}: {onEnter: (v: VendorId) => void}) {
  return (
    <>
      <div className="layer">
        <ArtSlot
          label="RUNNERS ROW — BACKDROP"
          hint="2560×1440 painted · the full strip, all six stalls, sodium lamps"
          ratio="16 / 9"
          className=""
        />
      </div>

      {VENDOR_ORDER.map((id) => {
        const r: Rect = ROW_HOTSPOTS[id];
        return (
          <button
            key={id}
            className="hotspot"
            style={{left: r.x, top: r.y, width: r.w, height: r.h}}
            onClick={() => onEnter(id)}
            aria-label={VENDORS[id].stallLabel}
          >
            <span className="hotspot-label">{VENDORS[id].stallLabel}</span>
          </button>
        );
      })}

      <div
        style={{
          position: 'absolute',
          left: 40,
          top: 44,
          zIndex: 40,
          pointerEvents: 'none',
        }}
      >
        <div className="logo" style={{fontSize: 40}}>
          AUG<span className="slash">//</span>RUN
        </div>
        <div
          className="mono"
          style={{fontSize: 12, letterSpacing: '0.24em', color: 'var(--dim)', marginTop: 4}}
        >
          RUNNERS ROW
        </div>
      </div>
    </>
  );
}

/* ----------------------------------------------------------------- SHOP */

function ShopScene({
  id,
  onBack,
  onSay,
}: {
  id: VendorId;
  onBack: () => void;
  onSay: (s: string) => void;
}) {
  const v = VENDORS[id];

  return (
    <>
      {/* Interior backdrop */}
      <div className="layer">
        <ArtSlot
          label={`${v.shop.toUpperCase()} — INTERIOR`}
          hint="2560×1440 painted"
          ratio="16 / 9"
          className=""
        />
      </div>

      {/* Vendor cutout, layered over the interior. The Terminal has nobody behind it — that
          absence is a design point in the spec, not an asset that hasn't arrived. */}
      {id !== 'terminal' && (
        <div className="vendor-sprite" style={{left: 60, width: 300}}>
          <ArtSlot label={v.name.toUpperCase()} hint="cutout · PNG alpha · 600×1000" ratio="3 / 5" />
        </div>
      )}

      <button className="btn sm scene-back" onClick={onBack}>
        ← back to the Row
      </button>

      {id === 'market' && <MarketScene onSay={onSay} />}
      {id === 'ripperdoc' && <RipperdocScene onSay={onSay} />}
      {id === 'terminal' && <TerminalScene onSay={onSay} />}
      {id === 'fixer' && <FixerScene onSay={onSay} />}
      {id === 'chopshop' && <ChopShopScene onSay={onSay} />}
      {id === 'drop' && <DropScene onSay={onSay} />}
    </>
  );
}
