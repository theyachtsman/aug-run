'use client';

import {useEffect, useState} from 'react';
import {GameShell} from '@/game/GameShell';
import {TerminalHome} from '@/components/TerminalHome';

/**
 * Runners Row.
 *
 * The scene is the default. Terminal mode is a real alternative rather than a degraded one — it
 * serves automatically on narrow screens, where a fixed 1280×720 stage with drag-and-drop would put
 * someone's assets out of reach, and it stays available by choice on any display.
 */
export default function Home() {
  const [mode, setMode] = useState<'game' | 'terminal' | null>(null);

  useEffect(() => {
    const saved = window.localStorage.getItem('augrun.mode');
    if (saved === 'game' || saved === 'terminal') return setMode(saved);
    setMode(window.innerWidth < 900 ? 'terminal' : 'game');
  }, []);

  const choose = (m: 'game' | 'terminal') => {
    window.localStorage.setItem('augrun.mode', m);
    setMode(m);
  };

  if (mode === null) return null; // avoid a flash of the wrong mode before we know the viewport

  return (
    <>
      {mode === 'game' ? <GameShell /> : <TerminalHome />}
      <button
        className="btn sm ghost mode-toggle"
        onClick={() => choose(mode === 'game' ? 'terminal' : 'game')}
      >
        {mode === 'game' ? 'terminal mode' : 'enter the Row'}
      </button>
    </>
  );
}
