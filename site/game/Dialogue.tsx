'use client';

import {useEffect, useRef, useState} from 'react';
import {ArtSlot} from '@/components/ArtSlot';

/**
 * The NPC dialogue box.
 *
 * Types a line out rather than snapping it in — the pacing is most of what makes a shopkeeper feel
 * like a character rather than a tooltip. Clicking (or pressing a key) completes the line
 * immediately, because forcing someone to wait through text they have already read is the fastest
 * way to make a charming effect annoying.
 */
export function Dialogue({
  speaker,
  portrait,
  line,
  onAdvance,
}: {
  speaker: string;
  portrait: string;
  line: string;
  onAdvance?: () => void;
}) {
  const [shown, setShown] = useState('');
  const [done, setDone] = useState(false);
  const lineRef = useRef(line);

  useEffect(() => {
    lineRef.current = line;
    setShown('');
    setDone(false);
    let i = 0;
    const t = setInterval(() => {
      i += 1;
      setShown(line.slice(0, i));
      if (i >= line.length) {
        clearInterval(t);
        setDone(true);
      }
    }, 18);
    return () => clearInterval(t);
  }, [line]);

  const complete = () => {
    if (!done) {
      setShown(lineRef.current);
      setDone(true);
    } else {
      onAdvance?.();
    }
  };

  return (
    <div className="dlg" onClick={complete}>
      <div className="dlg-portrait">
        <ArtSlot label={speaker} hint="portrait" ratio="1 / 1" />
      </div>
      <div className="dlg-body">
        <div className="dlg-name">{speaker}</div>
        <p className="dlg-text">
          {shown}
          {!done && <span className="dlg-caret">▍</span>}
        </p>
        {done && <span className="dlg-more">▼</span>}
      </div>
    </div>
  );
}
