'use client';

import Link from 'next/link';
import {useReadContracts} from 'wagmi';
import {addresses, isDeployed} from '@/lib/addresses';
import {StockRunnerAbi} from '@/lib/generated/abis';
import {fmt} from '@/lib/format';

/**
 * Whether the mint is open, stated plainly.
 *
 * `mintingOpen` is a one-way switch on the contract, not a UI toggle — while it is false nobody can
 * mint, including through a direct contract call. Saying so explicitly is better than a dead button:
 * a launch that hides its own state invites people to assume they were front-run.
 */
export function MintStatus() {
  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'mintingOpen'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'totalMinted'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'MAX_SUPPLY'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'GENESIS_PRICE'},
    ],
    query: {enabled: isDeployed},
  });

  /**
   * Fail CLOSED. `open` is only true when the contract explicitly says so — an undefined result
   * (RPC hiccup, or a StockRunner deployed before the gate existed, where the call reverts) must
   * never render as "mint is live". Showing an open mint that isn't is far worse than the reverse.
   */
  const open = data?.[0]?.result === true;
  const minted = data?.[1]?.result as bigint | undefined;
  const max = (data?.[2]?.result as bigint | undefined) ?? 333n;
  const price = data?.[3]?.result as bigint | undefined;

  if (!isDeployed) {
    return (
      <div className="notice">
        <div className="between">
          <div>
            <strong style={{color: 'var(--sodium)'}}>Not yet deployed</strong>
            <div className="dim" style={{fontSize: 12.5, marginTop: 4}}>
              The protocol is live on testnet while the collection is finished. $RUN launches first;
              the mint opens after.
            </div>
          </div>
        </div>
      </div>
    );
  }

  const pct = minted !== undefined ? Number((minted * 100n) / max) : 0;

  if (!open) {
    return (
      <div className="notice">
        <div className="between" style={{alignItems: 'flex-start'}}>
          <div style={{maxWidth: '58ch'}}>
            <div className="row" style={{gap: 8, marginBottom: 6}}>
              <span className="tag warn">Mint closed</span>
              <span className="faint mono" style={{fontSize: 11}}>
                enforced on-chain
              </span>
            </div>
            <strong style={{color: 'var(--sodium)'}}>Genesis has not opened.</strong>
            <div className="dim" style={{fontSize: 12.5, marginTop: 6}}>
              All 333 units are still sealed. Minting is gated in the contract itself — not hidden in
              this interface — so nobody can activate a unit ahead of you, by any route. When it
              opens it opens for everyone at once, and it can never be closed again.
            </div>
          </div>
          <div style={{textAlign: 'right', whiteSpace: 'nowrap'}}>
            <div className="faint" style={{fontSize: 10, letterSpacing: '0.14em'}}>
              GENESIS
            </div>
            <div className="mono" style={{fontSize: 19, color: 'var(--sodium)'}}>
              {fmt(price, 18, 0)}
            </div>
            <div className="faint mono" style={{fontSize: 11}}>
              $RUN per unit
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="panel">
      <div className="between" style={{alignItems: 'flex-start'}}>
        <div>
          <div className="row" style={{gap: 8, marginBottom: 6}}>
            <span className="tag on">Mint open</span>
          </div>
          <strong>Activate a blank Stock//Runner.</strong>
          <div className="dim" style={{fontSize: 12.5, marginTop: 4, maxWidth: '52ch'}}>
            Every unit mints at the same price with nothing to snipe — no whitelist, no reserve, no
            rarity to check. What it becomes is up to you.
          </div>
        </div>
        <Link href="/market" className="btn primary">
          activate — {fmt(price, 18, 0)} $RUN
        </Link>
      </div>

      <div style={{marginTop: 14}}>
        <div className="between mono" style={{fontSize: 11, marginBottom: 5}}>
          <span className="dim">
            {minted?.toString() ?? '—'} / {max.toString()} activated
          </span>
          <span className="dim">{pct}%</span>
        </div>
        <div style={{height: 4, background: 'var(--void)', borderRadius: 2, overflow: 'hidden'}}>
          <div
            style={{
              width: `${pct}%`,
              height: '100%',
              background: 'var(--chrome)',
              transition: 'width 0.4s',
            }}
          />
        </div>
      </div>
    </div>
  );
}
