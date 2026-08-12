/**
 * Turning a revert into something an operator can act on.
 *
 * Two problems to solve. Custom errors raised by a *different* contract than the one being called
 * cannot be decoded from the call's ABI — seating an Augment reverts with the $AUG token's
 * ERC20InsufficientAllowance, which is nowhere in the Ripperdoc ABI — so those are matched off the
 * raw 4-byte selector. And a bare error name is not an explanation: most of these reverts are the
 * protocol's *rules* firing correctly, so each one says what rule and what to do about it.
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

const GLOSS: Record<string, string> = {
  // ---- the protocol's own rules, firing as designed
  MintingNotOpen:
    'Genesis has not opened. Minting is gated in the contract itself, so nobody can activate a unit ahead of you.',
  SupplyExhausted: 'All 333 Stock//Runners have been activated. There is no mechanism to create more.',
  BayLockedThisCycle:
    'This bay was already changed this cycle. One rebind per bay per cycle — it unlocks at the next Monday 00:00 UTC boundary.',
  BayNotEmpty: 'That bay already holds an Augment. Swap it, or sell it back to the Ripperdoc first.',
  BayEmpty: 'That bay is empty — there is nothing to swap or sell back.',
  BayIndexOutOfRange: 'That bay is not open yet. Install an Expansion Module to open it.',
  BayCeilingReached: 'Three bays is the ceiling. Every unit shares it — no unit can out-scale another on slots.',
  NotUnitOwner: 'You do not own that Stock//Runner.',
  AlreadyCalibratedToday: 'One Calibration per unit per UTC day. Skipping never penalises — it only forgoes the acceleration.',
  PoolEmpty: 'The pool holds no units right now. Somebody has to sell one in first.',
  UnitNotInPool: 'That unit is not in the pool.',
  SlippageExceeded: 'The price moved past your limit. Refresh the quote and try again.',
  InsufficientPoolFunds: 'The pool does not hold enough $RUN to buy a unit right now.',
  LendCeilingReached: 'The Fixer may only borrow part of the pool, so it always keeps buying capacity.',
  NotIceable: 'That position is still healthy — it cannot be Iced yet.',
  LoanNotActive: 'That loan is already closed.',
  BadTerm: 'Term must be between 1 and 52 cycles.',
  InsufficientEthFee: 'The upfront rate is paid in ETH and this did not cover it.',
  BackingBelowFloor: 'Backing must be at least 25% of declared value, so a built item cannot be listed at trivial backing.',
  ListingClosed: 'That listing is closed — either a roll is outstanding or the table has rotated.',
  ListingStillOpen: 'The table has not rotated yet. Listings run a day.',
  RollNotReady: 'The target block has not landed yet. Give it a couple of blocks.',
  RollNotWon: 'That roll did not win.',
  NotExpired: 'That roll can still be resolved — it has not run out of time.',
  WrongPhase: 'The Drop is not in the right phase for that step.',
  AccumulationIncomplete: 'Weights are still being tallied. Keep accumulating before finalising.',
  NothingToDrop: 'There is nothing to distribute yet.',
  ClaimWindowClosed: 'The claim window closed. Unclaimed Drops are sold to fund a $RUN buyback.',
  ClaimWindowOpen: 'The claim window is still open.',
  AlreadyClaimed: 'Already collected.',
  InsufficientStake: 'You do not have that much staked.',
  LpTokenNotSet: 'No liquidity token is wired up yet.',
  NothingPulled: 'There is no revenue waiting to be pulled.',
  TestnetOnly: 'That control exists only on testnet deployments.',

  // ---- standard token errors
  ERC20InsufficientAllowance:
    'You have not approved this contract to spend your tokens yet. Approvals do not carry over when a contract is redeployed.',
  ERC20InsufficientBalance: 'Not enough tokens for that.',
  ERC1155InsufficientBalance:
    'You do not hold that Augment loose. Seated Augments are burned and bound permanently to their unit, so they cannot be moved.',
  ERC1155MissingApprovalForAll: 'Approve the item contract to move your Augments first.',
  ERC721InsufficientApproval: 'Approve this contract to move your units first.',
  OwnableUnauthorizedAccount: 'That action is owner-only.',
};

export function revertReason(err: unknown): string {
  if (!err) return '';
  const any = err as any;

  const walk = (e: any, depth = 0): string | undefined => {
    if (!e || depth > 8) return undefined;
    if (e.data?.errorName) return e.data.errorName;
    if (typeof e.errorName === 'string') return e.errorName;
    const raw = typeof e.data === 'string' ? e.data : e.raw;
    if (typeof raw === 'string' && raw.startsWith('0x') && raw.length >= 10) {
      const hit = SELECTORS[raw.slice(0, 10).toLowerCase()];
      if (hit) return hit;
    }
    return walk(e.cause, depth + 1);
  };

  const named = walk(any);
  if (named) return GLOSS[named] ?? named;

  const msg: string = any.shortMessage ?? any.details ?? any.message ?? String(err);
  if (/User rejected|denied transaction/i.test(msg)) return 'Rejected in your wallet.';

  const m = msg.match(/0x[0-9a-fA-F]{8}/);
  if (m && SELECTORS[m[0].toLowerCase()]) {
    const name = SELECTORS[m[0].toLowerCase()];
    return GLOSS[name] ?? name;
  }
  return msg.split('\n')[0];
}
