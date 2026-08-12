'use client';

import {useState} from 'react';

/**
 * The AUG//RUN mark.
 *
 * One component so the wordmark can never drift between the HUD and the Row. It renders
 * /art/logo.png and falls back to the typographic wordmark if that file is absent, so the site
 * works before the art lands and switches over the moment it does — no code change, no half-branded
 * state where one surface has the logo and another doesn't.
 *
 * The artwork is a wide drip mark on black. It is never given a background or padding of its own:
 * the black is already the page, so the mark sits directly on it.
 */
export function Logo({height = 34, className}: {height?: number; className?: string}) {
  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <span className={`logo ${className ?? ''}`} style={{fontSize: height * 0.72}}>
        AUG<span className="slash">//</span>RUN
      </span>
    );
  }

  return (
    <img
      src="/art/logo.png"
      alt="AUG//RUN"
      className={`logo-img ${className ?? ''}`}
      style={{height}}
      onError={() => setFailed(true)}
    />
  );
}
