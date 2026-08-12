import {formatUnits} from 'viem';

export function fmt(v: bigint | undefined, decimals = 18, dp = 2): string {
  if (v === undefined) return '—';
  const n = Number(formatUnits(v, decimals));
  return Number.isFinite(n) ? n.toLocaleString(undefined, {maximumFractionDigits: dp}) : '—';
}

/** Compact form for HUD readouts: 1.2M, 44.1k. */
export function fmtCompact(v: bigint | undefined, decimals = 18): string {
  if (v === undefined) return '—';
  const n = Number(formatUnits(v, decimals));
  if (!Number.isFinite(n)) return '—';
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
  return n.toLocaleString(undefined, {maximumFractionDigits: 2});
}

/** 1e18 fixed-point weights, e.g. "2.25x". */
export function fmtWeight(v: bigint | undefined): string {
  if (v === undefined) return '—';
  return `${(Number(v) / 1e18).toFixed(4).replace(/0+$/, '').replace(/\.$/, '')}x`;
}

export function shortAddr(a?: string): string {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—';
}

export function countdown(seconds: number): string {
  if (seconds <= 0) return '00:00';
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const p = (n: number) => String(n).padStart(2, '0');
  return d > 0 ? `${d}d ${p(h)}:${p(m)}:${p(s)}` : `${p(h)}:${p(m)}:${p(s)}`;
}

export function tierLabel(t?: number) {
  return t ? `T${t}` : '—';
}
