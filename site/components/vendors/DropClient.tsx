'use client';

import {useEffect, useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {DropAbi, RUNAbi, AugmentsAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight, countdown} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';
import {useOwnedUnits} from '@/components/Inventory';

const PHASE = ['—', 'Being weighed', 'Ready to collect', 'Closed'];
const ZERO = '0x0000000000000000000000000000000000000000';

/**
 * The Drop, in terminal mode.
 *
 * Same contract as the game scene: one button collects everything you are owed. Firing a Drop is
 * keeper work — `bin/run-drop.sh`, on a schedule — and deliberately has no controls here. An
 * operator arriving at the Courier should see what is held for them and collect it, not be handed
 * a three-step procedure they have to understand before their assets move.
 */
export function DropClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [, tick] = useState(0);

  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const {data: dropId} = useReadContract({
    address: addresses.Drop,
    abi: DropAbi,
    functionName: 'currentDropId',
  });
  const id = (dropId as bigint | undefined) ?? 0n;

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Drop, abi: DropAbi, functionName: 'rounds', args: [id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'buybackPool'},
      {address: addresses.Drop, abi: DropAbi, functionName: 'skippedPool', args: [id]},
    ],
    query: {enabled: id > 0n},
  });

  const round = data?.[0]?.result as readonly bigint[] | undefined;
  const buyback = data?.[1]?.result as bigint | undefined;
  const skipped = data?.[2]?.result as bigint | undefined;

  const {data: shelf} = useReadContracts({
    contracts: owned.flatMap((u) => [
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimable' as const, args: [id, BigInt(u)]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimed' as const, args: [id, BigInt(u)]},
    ]),
    query: {enabled: id > 0n && owned.length > 0 && !!address},
  });

  if (!isConnected) return <NotConnected />;

  const phase = round ? Number(round[6]) : 0;
  const pool = round?.[1];
  const totalWeight = round?.[2];
  const deadline = Number(round?.[5] ?? 0n);
  const now = Math.floor(Date.now() / 1000);
  const ready = phase === 2 && deadline > now;

  const units = owned.map((u, i) => {
    const res = shelf?.[i * 2]?.result as
      | readonly [readonly `0x${string}`[], readonly bigint[]]
      | undefined;
    const assets = res?.[0] ?? [];
    const amounts = res?.[1] ?? [];
    return {
      tokenId: u,
      claimed: (shelf?.[i * 2 + 1]?.result as boolean | undefined) ?? false,
      lots: assets
        .map((a, b) => ({asset: a, amount: amounts[b] ?? 0n}))
        .filter((l) => l.asset !== ZERO && l.amount > 0n),
    };
  });

  const waiting = units.filter((u) => !u.claimed && u.lots.length > 0);
  const totalLots = waiting.reduce((n, u) => n + u.lots.length, 0);

  return (
    <>
      <section className="panel" style={{marginBottom: 16}}>
        <div className="between" style={{alignItems: 'center', gap: 20}}>
          <div>
            <h2 style={{marginBottom: 6}}>
              {!ready
                ? 'Nothing to collect yet'
                : waiting.length === 0
                  ? 'Nothing held for you'
                  : `${totalLots} lot${totalLots === 1 ? '' : 's'} waiting`}
            </h2>
            <p className="dim" style={{fontSize: 12.5, margin: 0, maxWidth: '58ch'}}>
              {!ready
                ? phase === 1
                  ? 'This cycle’s collection is still being weighed. Come back shortly.'
                  : 'This cycle’s packages have not arrived yet. They land once a cycle.'
                : waiting.length === 0
                  ? units.some((u) => u.claimed)
                    ? 'Already collected — it went into your units’ own wallets.'
                    : 'No bay of yours was earning when this Drop was weighed.'
                  : `Across ${waiting.length} unit${waiting.length === 1 ? '' : 's'}. One transaction collects all of it.`}
            </p>
          </div>

          {ready && waiting.length > 0 && (
            <button
              className="btn primary"
              style={{fontSize: 14, padding: '12px 22px', whiteSpace: 'nowrap'}}
              disabled={busy}
              onClick={() =>
                send(
                  waiting.length === 1
                    ? `collect for #${waiting[0].tokenId}`
                    : `collect for ${waiting.length} units`,
                  {
                    address: addresses.Drop,
                    abi: DropAbi,
                    functionName: 'claimMany',
                    args: [id, waiting.map((u) => BigInt(u.tokenId))],
                  },
                )
              }
            >
              Collect everything
            </button>
          )}
        </div>

        {ready && (
          <div style={{marginTop: 14}}>
            <Stat k="Window closes" v={countdown(deadline - now)} sub="one hour before the next Drop" />
          </div>
        )}

        <Rule>
          Assets land in each unit&apos;s own wallet rather than yours, so its position and PnL belong
          to the machine and travel with it when it sells. Anything left when the window closes is
          sold to fund a $RUN buyback: a unit whose operator doesn&apos;t show up funds the operators
          who did.
        </Rule>
      </section>

      {units.length > 0 && (
        <section className="panel" style={{marginBottom: 16}}>
          <h2 style={{marginBottom: 10}}>Your units</h2>
          <table>
            <thead>
              <tr>
                <th>unit</th>
                <th>held for it</th>
                <th style={{textAlign: 'right'}}>state</th>
              </tr>
            </thead>
            <tbody>
              {units.map((u) => (
                <tr key={u.tokenId}>
                  <td>#{String(u.tokenId).padStart(4, '0')}</td>
                  <td>
                    {u.lots.length === 0 ? (
                      <span className="dim">nothing this cycle</span>
                    ) : (
                      <span className="row" style={{gap: 6}}>
                        {u.lots.map((l, i) => (
                          <LotTag key={i} asset={l.asset} amount={l.amount} />
                        ))}
                      </span>
                    )}
                  </td>
                  <td style={{textAlign: 'right'}}>
                    {u.claimed ? (
                      <span className="tag">collected</span>
                    ) : u.lots.length > 0 ? (
                      <span className="tag on">waiting</span>
                    ) : (
                      <span className="dim">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      <section className="panel">
        <h2 style={{marginBottom: 10}}>This cycle</h2>
        <Stat k="Drop" v={`#${id.toString()} · ${PHASE[phase]}`} />
        <Stat k="Pool committed" v={`${fmt(pool, 18, 0)} $RUN`} accent />
        <Stat k="Total eligible weight" v={fmtWeight(totalWeight)} />
        <Stat k="Rolled forward" v={`${fmt(skipped, 18, 0)} $RUN`} sub="unavailable tickers" />
        <Stat k="Buyback pool" v={`${fmt(buyback, 18, 0)} $RUN`} sub="from Drops nobody collected" />
        <Rule>
          Opening, weighing and buying are permissionless keeper steps run on a schedule by
          <code> bin/run-drop.sh</code>. Weights are read from the Stock//Runners themselves and never
          supplied by anyone, so whoever fires a Drop chooses only <em>when</em> it happens — never
          who earns from it.
        </Rule>
      </section>
    </>
  );
}

/** Compact asset chip that reads the token's own symbol and decimals. */
function LotTag({asset, amount}: {asset: `0x${string}`; amount: bigint}) {
  const {data} = useReadContracts({
    contracts: [
      {address: asset, abi: RUNAbi, functionName: 'symbol'},
      {address: asset, abi: RUNAbi, functionName: 'decimals'},
    ],
  });
  const symbol = (data?.[0]?.result as string | undefined) ?? '···';
  const decimals = Number((data?.[1]?.result as number | undefined) ?? 18);
  return (
    <span className="tag on mono">
      {fmt(amount, decimals, 4)} {symbol}
    </span>
  );
}
