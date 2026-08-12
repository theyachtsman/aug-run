import {formatUnits} from 'viem';

/** Token amounts, trimmed. */
export function fmt(value: bigint | undefined, decimals = 18, dp = 2): string {
  if (value === undefined) return '—';
  const s = formatUnits(value, decimals);
  const n = Number(s);
  if (Number.isFinite(n)) {
    return n.toLocaleString(undefined, {maximumFractionDigits: dp});
  }
  return s;
}

/** 1e18 fixed-point weights, shown as e.g. "2.25x". */
export function fmtWeight(value: bigint | undefined): string {
  if (value === undefined) return '—';
  return `${(Number(value) / 1e18).toFixed(4).replace(/0+$/, '').replace(/\.$/, '')}x`;
}

export function shortAddr(a?: string): string {
  if (!a) return '—';
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

/** Seconds -> "2d 14h 03m 12s". */
export function countdown(seconds: number): string {
  if (seconds <= 0) return '00s';
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const pad = (n: number) => String(n).padStart(2, '0');
  return [d ? `${d}d` : '', d || h ? `${pad(h)}h` : '', `${pad(m)}m`, `${pad(s)}s`]
    .filter(Boolean)
    .join(' ');
}

/**
 * Pull something readable out of a wagmi/viem write error.
 *
 * The contracts revert with named custom errors (BayLockedThisCycle, NotUnitOwner,
 * BayNotEmpty, …) and those names ARE the explanation of which rule blocked the
 * action, so surface them rather than a generic failure string.
 */
/**
 * Custom errors raised by a *different* contract than the one being called cannot be decoded from
 * the call's ABI — e.g. seating an Augment reverts with the $AUG token's
 * ERC20InsufficientAllowance, which is nowhere in the Ripperdoc ABI. viem then surfaces only raw
 * hex, which reads as an unexplained failure. These are the standard OZ selectors, matched directly
 * off the revert payload so those cases still get a name.
 */
const SELECTORS: Record<string, string> = {
  '0xfb8f41b2': 'ERC20InsufficientAllowance',
  '0xe450d38c': 'ERC20InsufficientBalance',
  '0xec442f05': 'ERC20InvalidReceiver',
  '0x03dee4c5': 'ERC1155InsufficientBalance',
  '0xe237d922': 'ERC1155MissingApprovalForAll',
  '0x177e802f': 'ERC721InsufficientApproval',
  '0x7e273289': 'ERC721NonexistentToken',
  '0x64283d7b': 'ERC721IncorrectOwner',
  '0x118cdaa7': 'OwnableUnauthorizedAccount',
};

export function revertReason(err: unknown): string {
  if (!err) return '';
  const any = err as any;

  const walk = (e: any, depth = 0): string | undefined => {
    if (!e || depth > 8) return undefined;
    if (e.data?.errorName) return e.data.errorName;
    if (typeof e.errorName === 'string') return e.errorName;
    // Fall back to matching the raw revert payload's 4-byte selector.
    const raw = typeof e.data === 'string' ? e.data : e.raw;
    if (typeof raw === 'string' && raw.startsWith('0x') && raw.length >= 10) {
      const hit = SELECTORS[raw.slice(0, 10).toLowerCase()];
      if (hit) return hit;
    }
    return walk(e.cause, depth + 1);
  };

  const named = walk(any);
  if (named) return explain(named);

  const msg: string = any.shortMessage ?? any.details ?? any.message ?? String(err);
  if (/User rejected|denied transaction/i.test(msg)) return 'Rejected in wallet.';

  // Last resort: the selector may only appear in the message text.
  const m = msg.match(/0x[0-9a-fA-F]{8}/);
  if (m && SELECTORS[m[0].toLowerCase()]) return explain(SELECTORS[m[0].toLowerCase()]);

  return msg.split('\n')[0];
}

/** Plain-English gloss for the rules that most often block an action. */
const GLOSS: Record<string, string> = {
  BayLockedThisCycle:
    'BayLockedThisCycle — this bay was already changed this cycle. One rebind per bay per cycle; it unlocks at the next Monday 00:00 UTC boundary.',
  BayNotEmpty: 'BayNotEmpty — that bay already holds an Augment. Use Swap, or sell it back first.',
  BayEmpty: 'BayEmpty — that bay is empty, so there is nothing to sell back or swap.',
  BayIndexOutOfRange:
    'BayIndexOutOfRange — that bay is not open yet. Install an Expansion Module to open it.',
  BayCeilingReached: 'BayCeilingReached — three bays is the ceiling. Max two Expansion Modules per unit.',
  NotUnitOwner: 'NotUnitOwner — you do not own that Stock//Runner.',
  AlreadyCalibratedToday: 'AlreadyCalibratedToday — one Calibration per unit per UTC day.',
  SupplyExhausted: 'SupplyExhausted — all 333 Stock//Runners have been activated.',
  FaucetCooldownActive: 'FaucetCooldownActive — faucet has a 1 hour per-address cooldown.',
  FaucetDisabled: 'FaucetDisabled — this is not a testnet deployment.',
  FaucetDrained: 'FaucetDrained — the faucet reserve is empty.',
  TestnetOnly: 'TestnetOnly — cycle fast-forward exists only on testnet deployments.',
  ERC20InsufficientAllowance:
    'ERC20InsufficientAllowance — you have not approved $AUG (or $RUN) for this contract yet. Use the approve button in the panel above. Approvals do not carry over when a contract is redeployed.',
  ERC20InsufficientBalance:
    'ERC20InsufficientBalance — not enough tokens. Use the faucet in the Wallet panel.',
  ERC721InsufficientApproval:
    'ERC721InsufficientApproval — approve the Black Market to move your units before selling.',
  ERC1155MissingApprovalForAll: 'ERC1155MissingApprovalForAll — approve the item contract first.',
  OwnableUnauthorizedAccount: 'OwnableUnauthorizedAccount — that action is owner-only.',
  ERC1155InsufficientBalance:
    'ERC1155InsufficientBalance — you do not hold that Augment loose. Seated Augments are burned and permanently bound to their unit, so they cannot be moved to another one.',
  NotRipperdoc: 'NotRipperdoc — only the Ripperdoc may change bay state.',
};

function explain(name: string): string {
  return GLOSS[name] ?? name;
}
