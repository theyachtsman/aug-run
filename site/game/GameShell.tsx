'use client';

import {useCallback, useEffect, useState} from 'react';
import {Stage} from './Stage';
import {Dissolve} from './Dissolve';
import {Dialogue} from './Dialogue';
import {DragProvider} from './dnd';
import {ROW_HOTSPOTS, type Rect} from './stage';
import {VENDORS, VENDOR_ORDER, line, type VendorId} from './vendors';
import {ArtSlot} from '@/components/ArtSlot';
import {Logo} from '@/components/Logo';
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
  // Hold H to outline the stall hotspots over the art. The backdrop will be replaced more than
  // once before launch and every replacement moves the shopfronts, so retuning needs to be a
  // look-and-adjust loop rather than a guess-and-click one.
  const [debug, setDebug] = useState(false);
  useEffect(() => {
    const down = (e: KeyboardEvent) => e.key.toLowerCase() === 'h' && setDebug(true);
    const up = (e: KeyboardEvent) => e.key.toLowerCase() === 'h' && setDebug(false);
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
    };
  }, []);

  return (
    <>
      <div className="layer">
        <ArtSlot
          label="RUNNERS ROW — BACKDROP"
          hint="2560×1440 painted · the full strip, all six stalls, sodium lamps"
          ratio="16 / 9"
          className=""
          src="/art/row-backdrop.png"
        />
      </div>

      {VENDOR_ORDER.map((id) => {
        const r: Rect = ROW_HOTSPOTS[id];
        return (
          <button
            key={id}
            className={`hotspot ${debug ? 'debug' : ''}`}
            style={{left: r.x, top: r.y, width: r.w, height: r.h}}
            onClick={() => onEnter(id)}
            aria-label={VENDORS[id].stallLabel}
          >
            <span className="hotspot-label">{VENDORS[id].stallLabel}</span>
            {debug && (
              <span className="hotspot-coords mono">
                {id}
                <br />
                {r.x},{r.y}
                <br />
                {r.w}×{r.h}
              </span>
            )}
          </button>
        );
      })}

      {/* The mark is ~3:1, so 110 tall renders ~331 wide — filling the quiet top-left region the
          backdrop reserves without crowding the first stall, which starts at x 34. */}
      <div className="row-brand">
        <Logo height={110} />
        <div
          className="mono"
          style={{fontSize: 12, letterSpacing: '0.24em', color: 'var(--dim)', marginTop: -4}}
        >
          RUNNERS ROW
        </div>
      </div>

      <div className="row-hint faint mono">hold H to show stall hotspots</div>
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
      {/* Interior backdrop. Each shop reads its own file, so interiors can land one at a time. */}
      <div className="layer">
        <ArtSlot
          label={`${v.shop.toUpperCase()} — INTERIOR`}
          hint="2560×1440 painted"
          ratio="16 / 9"
          className=""
          src={`/art/interior-${id}.png`}
        />
      </div>

      {/* Vendor cutout, layered over the interior. The Terminal has nobody behind it — that
          absence is a design point in the spec, not an asset that hasn't arrived. */}
      {id !== 'terminal' && (
        <div className="vendor-sprite" style={{left: 60, width: 300}}>
          <ArtSlot
            label={v.name.toUpperCase()}
            hint="cutout · PNG alpha · 600×1000"
            ratio="3 / 5"
            src={`/art/vendor-${id}.png`}
            fit="contain"
          />
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
