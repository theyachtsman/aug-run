'use client';

import {
  createContext,
  useCallback,
  useContext,
  useRef,
  useState,
  type ReactNode,
  type PointerEvent as ReactPointerEvent,
} from 'react';

/**
 * Inventory drag and drop.
 *
 * Built on pointer events rather than HTML5 drag-and-drop, for three reasons: HTML5 drag images
 * cannot be styled to look like a game item, it does not work on touch, and it fights the scaled
 * stage. Here the held item is a real element following the cursor, and the drop target is resolved
 * with elementFromPoint — which is scale-agnostic.
 */

export type DragItem = {
  kind: 'augment' | 'module';
  id: number;
  label: string;
  tier?: number;
};

type Ctx = {
  held: DragItem | null;
  begin: (item: DragItem, e: ReactPointerEvent) => void;
  registerTarget: (el: HTMLElement | null, accept: (i: DragItem) => boolean, onDrop: (i: DragItem) => void) => void;
};

const DragContext = createContext<Ctx | null>(null);

export function DragProvider({children}: {children: ReactNode}) {
  const [held, setHeld] = useState<DragItem | null>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const targets = useRef(
    new Map<HTMLElement, {accept: (i: DragItem) => boolean; onDrop: (i: DragItem) => void}>(),
  );

  const registerTarget: Ctx['registerTarget'] = useCallback((el, accept, onDrop) => {
    if (!el) return;
    targets.current.set(el, {accept, onDrop});
  }, []);

  const begin = useCallback((item: DragItem, e: ReactPointerEvent) => {
    e.preventDefault();
    setHeld(item);

    const move = (ev: PointerEvent) => {
      const g = ghostRef.current;
      if (g) {
        g.style.left = `${ev.clientX}px`;
        g.style.top = `${ev.clientY}px`;
      }
      // Highlight whatever is under the cursor.
      const under = document.elementFromPoint(ev.clientX, ev.clientY);
      targets.current.forEach((_, el) => el.classList.remove('drop-hot'));
      for (const [el, t] of targets.current) {
        if (under && el.contains(under) && t.accept(item)) {
          el.classList.add('drop-hot');
          break;
        }
      }
    };

    const up = (ev: PointerEvent) => {
      const under = document.elementFromPoint(ev.clientX, ev.clientY);
      for (const [el, t] of targets.current) {
        if (under && el.contains(under) && t.accept(item)) {
          t.onDrop(item);
          break;
        }
      }
      targets.current.forEach((_, el) => el.classList.remove('drop-hot'));
      setHeld(null);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };

    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  }, []);

  return (
    <DragContext.Provider value={{held, begin, registerTarget}}>
      {children}
      {held && (
        <div ref={ghostRef} className="drag-ghost">
          <div className={`item-chip t${held.tier ?? 0}`}>{held.label}</div>
        </div>
      )}
    </DragContext.Provider>
  );
}

export function useDrag() {
  const c = useContext(DragContext);
  if (!c) throw new Error('useDrag must be used inside DragProvider');
  return c;
}

/** A slot that accepts dropped items. */
export function DropSlot({
  accept,
  onDrop,
  className,
  children,
}: {
  accept: (i: DragItem) => boolean;
  onDrop: (i: DragItem) => void;
  className?: string;
  children: ReactNode;
}) {
  const {registerTarget} = useDrag();
  return (
    <div ref={(el) => registerTarget(el, accept, onDrop)} className={className}>
      {children}
    </div>
  );
}
