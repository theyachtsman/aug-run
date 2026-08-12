'use client';

import {useEffect, useState} from 'react';
import Link from 'next/link';
import {useAccount, useConnect, useDisconnect, useReadContracts, useSwitchChain} from 'wagmi';
import {ACTIVE_CHAIN} from '@/lib/chain';
import {addresses, isDeployed} from '@/lib/addresses';
import {RUNAbi, AUGAbi, StockRunnerAbi} from '@/lib/generated/abis';
import {fmtCompact, shortAddr, countdown} from '@/lib/format';
import {Inventory} from './Inventory';
import {Logo} from './Logo';

/**
 * The persistent operator HUD. Always visible, on the Row and inside every vendor — the machine's
 * readout rather than a website navbar. Carries the one clock the whole protocol runs on, and the
 * button that opens your Stock//Runner inventory without leaving where you are.
 */
export function Hud() {
  const {address, isConnected, chainId} = useAccount();
  const {connect, connectors, isPending} = useConnect();
  const {disconnect} = useDisconnect();
  const {switchChain} = useSwitchChain();
  const [invOpen, setInvOpen] = useState(false);
  const [, tick] = useState(0);

  // Local ticker so the cycle countdown moves without hammering the RPC.
  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'currentCycle'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'nextCycleBoundary'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'balanceOf', args: [address!]},
    ],
    query: {enabled: !!address && isDeployed},
  });

  const run = data?.[0]?.result as bigint | undefined;
  const aug = data?.[1]?.result as bigint | undefined;
  const cycle = data?.[2]?.result as bigint | undefined;
  const boundary = Number((data?.[3]?.result as bigint | undefined) ?? 0n);
  const owned = data?.[4]?.result as bigint | undefined;

  const now = Math.floor(Date.now() / 1000);
  const wrongChain = isConnected && chainId !== ACTIVE_CHAIN.id;

  return (
    <>
      <header className="hud">
        <Link href="/" className="hud-brand" style={{textDecoration: 'none'}}>
          <Logo height={30} />
        </Link>

        {isConnected && !wrongChain && isDeployed && (
          <>
            <div className="hud-stat">
              <span className="k">Cycle</span>
              <span className="v">{cycle?.toString() ?? '—'}</span>
            </div>
            <div className="hud-stat">
              <span className="k">Next drop</span>
              <span className="v">{boundary > now ? countdown(boundary - now) : '—'}</span>
            </div>
            <div className="hud-stat">
              <span className="k">$RUN</span>
              <span className="v">{fmtCompact(run)}</span>
            </div>
            <div className="hud-stat">
              <span className="k">$AUG</span>
              <span className="v">{fmtCompact(aug)}</span>
            </div>
          </>
        )}

        <div className="hud-spacer" />

        {wrongChain && (
          <button className="btn" onClick={() => switchChain({chainId: ACTIVE_CHAIN.id})}>
            switch to {ACTIVE_CHAIN.name}
          </button>
        )}

        {isConnected && !wrongChain && (
          <button className="btn" onClick={() => setInvOpen(true)}>
            Stock//Runner Inventory
            {owned !== undefined && owned > 0n && (
              <span className="tag on" style={{marginLeft: 8}}>
                {owned.toString()}
              </span>
            )}
          </button>
        )}

        {isConnected ? (
          <button className="btn ghost mono" onClick={() => disconnect()}>
            {shortAddr(address)}
          </button>
        ) : (
          connectors.slice(0, 1).map((c) => (
            <button
              key={c.uid}
              className="btn primary"
              disabled={isPending}
              onClick={() => connect({connector: c})}
            >
              connect wallet
            </button>
          ))
        )}
      </header>

      {invOpen && <Inventory onClose={() => setInvOpen(false)} />}
    </>
  );
}
