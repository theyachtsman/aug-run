'use client';

import {useEffect, useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {DropAbi, AugmentsAbi, RUNAbi, RipperdocAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight, countdown} from '@/lib/format';
import {useOwnedUnits} from '@/components/Inventory';
import {line} from '../vendors';
import {hardware} from '../augmentNames';
import {CentrePanel, BigStat, Line} from '../CentrePanel';

const ZERO = '0x0000000000000000000000000000000000000000';

/**
 * The Courier's window.
 *
 * One button. If something is waiting you press it and everything you are owed goes into your
 * units' wallets in a single transaction; if nothing is waiting there is no button to press.
 *
 * Firing a Drop is three on-chain steps and cannot be fewer — 333 units' weights will not fit in
 * one transaction, and the aggregate purchase can only happen once every weight is known. But that
 * is operations, not gameplay, so it lives in `bin/run-drop.sh` on a schedule and never in front of
 * an operator standing at the counter. The Courier holds; you collect.
 */
export function DropScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [pick, setPick] = useState<number | undefined>();
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
    ],
    query: {enabled: id > 0n},
  });

  const round = data?.[0]?.result as readonly bigint[] | undefined;
  const buyback = data?.[1]?.result as bigint | undefined;

  const phase = round ? Number(round[6]) : 0;
  const deadline = Number(round?.[5] ?? 0n);
  const now = Math.floor(Date.now() / 1000);
  const ready = phase === 2 && deadline > now;

  // Which of your units actually have something on the shelf. This is what the button acts on, so
  // it is computed once here and drives the count, the button and the cards alike.
  //
  // Eligible weight is read alongside it because the commonest confusion at this counter is a unit
  // that is plainly earning yet has nothing waiting: a Drop pays out the weights snapshotted when
  // it was weighed, so a bay seated afterwards is simply not in that round. Without showing the
  // weight it carries forward, that reads as the Drop being broken.
  const {data: shelf} = useReadContracts({
    contracts: owned.flatMap((u) => [
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimable' as const, args: [id, BigInt(u)]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimed' as const, args: [id, BigInt(u)]},
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'unitEligibleWeight' as const,
        args: [BigInt(u)],
      },
    ]),
    query: {enabled: id > 0n && owned.length > 0 && !!address},
  });

  const units = owned.map((u, i) => {
    const amounts =
      (shelf?.[i * 3]?.result as readonly [unknown, readonly bigint[]] | undefined)?.[1] ?? [];
    const claimed = (shelf?.[i * 3 + 1]?.result as boolean | undefined) ?? false;
    const eligible = (shelf?.[i * 3 + 2]?.result as bigint | undefined) ?? 0n;
    return {tokenId: u, lots: amounts.filter((a) => a > 0n).length, claimed, eligible};
  });

  const waiting = units.filter((u) => !u.claimed && u.lots > 0);
  const totalLots = waiting.reduce((n, u) => n + u.lots, 0);

  // Units earning now that got nothing from this round — seated after it was weighed.
  const nextRound = units.filter((u) => u.lots === 0 && !u.claimed && u.eligible > 0n);
  const nextWeight = nextRound.reduce((w, u) => w + u.eligible, 0n);
  const selected = pick ?? waiting[0]?.tokenId ?? owned[0];
  const closing = deadline > now && deadline - now < 86_400;

  const collect = () => {
    onSay(line('drop', closing ? 'expiring' : 'collect'));
    send(
      waiting.length === 1 ? `collect for #${waiting[0].tokenId}` : `collect for ${waiting.length} units`,
      {
        address: addresses.Drop,
        abi: DropAbi,
        functionName: 'claimMany',
        args: [id, waiting.map((u) => BigInt(u.tokenId))],
      },
    );
  };

  return (
    <>
      <Package dropId={id} tokenId={selected} />

      <div className="shop-menu">
        <div className="between" style={{marginBottom: 14}}>
          <h3 style={{margin: 0}}>The Window</h3>
          <span className="mono faint" style={{fontSize: 11}}>
            drop #{id.toString()}
          </span>
        </div>

        {/* The one thing this shop is for. */}
        <div className="collect-block">
          {!ready ? (
            <>
              <BigStat value="—" label="NOTHING TO COLLECT YET" />
              <p className="faint" style={{fontSize: 11.5, textAlign: 'center', margin: '4px 0 0'}}>
                {phase === 1
                  ? 'The Courier is still weighing this week&rsquo;s collection. Come back shortly.'
                  : 'This week&rsquo;s packages have not arrived yet. They land once a cycle.'}
              </p>
            </>
          ) : waiting.length === 0 ? (
            <>
              <BigStat value="0" label="NOTHING HELD FOR YOU" />
              <p className="faint" style={{fontSize: 11.5, textAlign: 'center', margin: '4px 0 0'}}>
                {units.every((u) => u.claimed || u.eligible === 0n) && units.some((u) => u.claimed)
                  ? 'Already collected. It went into your units’ own wallets.'
                  : 'No bay of yours was earning when this Drop was weighed.'}
              </p>
            </>
          ) : (
            <>
              <BigStat
                value={String(totalLots)}
                label={`LOT${totalLots === 1 ? '' : 'S'} ACROSS ${waiting.length} UNIT${
                  waiting.length === 1 ? '' : 'S'
                }`}
                tone="lime"
              />
              <button
                className="btn primary collect-btn"
                disabled={busy}
                onMouseEnter={() => onSay(line('drop', 'collect'))}
                onClick={collect}
              >
                COLLECT EVERYTHING
              </button>
              <p className="faint" style={{fontSize: 11, textAlign: 'center', margin: '8px 0 0'}}>
                One transaction. Assets land in each unit&apos;s own wallet, not yours — the position
                belongs to the machine and travels with it when it sells.
              </p>
            </>
          )}
        </div>

        {ready && (
          <Line
            k="window closes"
            v={countdown(deadline - now)}
            tone={closing ? 'sodium' : undefined}
          />
        )}

        {/* Carrying weight but paid nothing is the confusing case, so name it explicitly rather
            than leaving an earning unit looking like a broken one. */}
        {nextRound.length > 0 && (
          <div className="notice" style={{marginTop: 10, padding: '9px 11px'}}>
            <span style={{fontSize: 11.5}}>
              {nextRound.length === 1
                ? `Unit #${String(nextRound[0].tokenId).padStart(4, '0')} carries`
                : `${nextRound.length} of your units carry`}{' '}
              <strong style={{color: 'var(--lime)'}}>{fmtWeight(nextWeight)}</strong> into the next
              Drop. {nextRound.length === 1 ? 'It was' : 'They were'} seated after this one was
              weighed — a Drop pays out the weights it snapshotted, so {nextRound.length === 1 ? 'it earns' : 'they earn'}{' '}
              from the next round rather than this one.
            </span>
          </div>
        )}

        {owned.length > 0 && (
          <>
            <h3 style={{margin: '14px 0 8px'}}>Your units</h3>
            <div
              className="grid"
              style={{gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 6}}
            >
              {units.map((u) => (
                <button
                  key={u.tokenId}
                  className={`unit-card ${selected === u.tokenId ? 'selected' : ''}`}
                  onClick={() => setPick(u.tokenId)}
                >
                  <div className="uid">#{String(u.tokenId).padStart(4, '0')}</div>
                  <div className="umodel">
                    {u.claimed
                      ? 'collected'
                      : u.lots > 0
                        ? `${u.lots} lot${u.lots === 1 ? '' : 's'}`
                        : u.eligible > 0n
                          ? 'next drop'
                          : 'nothing'}
                  </div>
                  {!u.claimed && u.lots > 0 && <span className="pip" />}
                </button>
              ))}
            </div>
          </>
        )}

        <p className="faint" style={{fontSize: 11, marginTop: 12, marginBottom: 0}}>
          Anything left when the window closes is sold to fund a $RUN buyback — {fmt(buyback, 18, 0)}{' '}
          $RUN has built up that way. A unit whose operator does not show up funds the ones who did.
        </p>
      </div>
    </>
  );
}

/* --------------------------------------------------------------- PACKAGE */

/** What is actually on the shelf for one unit, asset by asset. Display only — collecting is one
 *  button on the menu, so there is deliberately no second way to do it from in here. */
function Package({dropId, tokenId}: {dropId: bigint; tokenId?: number}) {
  const id = BigInt(tokenId ?? 0);
  const enabled = tokenId !== undefined && dropId > 0n;

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimable', args: [dropId, id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimed', args: [dropId, id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'bayAugmentAt', args: [dropId, id, 0]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'bayAugmentAt', args: [dropId, id, 1]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'bayAugmentAt', args: [dropId, id, 2]},
    ],
    query: {enabled},
  });

  const claimable = data?.[0]?.result as
    | readonly [readonly `0x${string}`[], readonly bigint[]]
    | undefined;
  const claimed = data?.[1]?.result as boolean | undefined;
  const augIds = [2, 3, 4].map((i) => data?.[i]?.result as bigint | undefined);

  const assets = claimable?.[0] ?? [];
  const amounts = claimable?.[1] ?? [];
  const lots = assets
    .map((a, i) => ({asset: a, amount: amounts[i] ?? 0n, augmentId: augIds[i], bay: i}))
    .filter((l) => l.asset !== ZERO && l.amount > 0n);

  if (tokenId === undefined) {
    return (
      <CentrePanel title="NO PACKAGE" sub="nothing selected">
        <div className="faint" style={{fontSize: 12, textAlign: 'center', marginTop: 40}}>
          You hold no units, so there is nothing on the Courier&apos;s shelf.
        </div>
      </CentrePanel>
    );
  }

  return (
    <CentrePanel
      title={`PACKAGE · #${String(tokenId).padStart(4, '0')}`}
      sub={claimed ? 'collected' : lots.length > 0 ? `${lots.length} lot(s) held` : 'shelf empty'}
    >
      {claimed ? (
        <div className="parcel collected">
          <div className="parcel-mark mono">COLLECTED</div>
          <div className="faint" style={{fontSize: 11.5, marginTop: 8}}>
            Gone into this unit&apos;s own wallet. It travels with the machine if you sell it.
          </div>
        </div>
      ) : lots.length === 0 ? (
        <div className="parcel">
          <div className="parcel-mark mono">NOTHING HELD</div>
          <div className="faint" style={{fontSize: 11.5, marginTop: 8}}>
            Seated too late, or seated nothing at all. A bay earns from the cycle after it is filled.
          </div>
        </div>
      ) : (
        <div className="lots">
          {lots.map((l) => (
            <Lot key={l.bay} asset={l.asset} amount={l.amount} augmentId={l.augmentId} />
          ))}
        </div>
      )}
    </CentrePanel>
  );
}

/** One asset lot. Reads the asset's own symbol and decimals so real RWA tokens format correctly. */
function Lot({
  asset,
  amount,
  augmentId,
}: {
  asset: `0x${string}`;
  amount: bigint;
  augmentId?: bigint;
}) {
  const {data} = useReadContracts({
    contracts: [
      {address: asset, abi: RUNAbi, functionName: 'symbol'},
      {address: asset, abi: RUNAbi, functionName: 'decimals'},
      {
        address: addresses.Augments,
        abi: AugmentsAbi,
        functionName: 'tickerOf',
        args: [augmentId ?? 0n],
      },
    ],
    query: {enabled: !!asset},
  });

  const symbol = (data?.[0]?.result as string | undefined) ?? '···';
  const decimals = Number((data?.[1]?.result as number | undefined) ?? 18);
  const ticker = (data?.[2]?.result as string | undefined) ?? '';
  const hw = ticker ? hardware(ticker) : undefined;

  return (
    <div className="lot">
      <div>
        <div className="lot-sym mono">{symbol}</div>
        {hw && <div className="lot-hw">via {hw.name}</div>}
      </div>
      <div className="lot-amt mono">{fmt(amount, decimals, 4)}</div>
    </div>
  );
}
