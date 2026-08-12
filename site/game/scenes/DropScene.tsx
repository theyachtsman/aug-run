'use client';

import {useEffect, useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {DropAbi, RevenueSplitterAbi, AugmentsAbi, RUNAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight, countdown} from '@/lib/format';
import {useOwnedUnits} from '@/components/Inventory';
import {line} from '../vendors';
import {hardware} from '../augmentNames';
import {CentrePanel, Line} from '../CentrePanel';

const PHASE = ['—', 'Weighing the collection', 'Ready to collect', 'Closed'];
const ZERO = '0x0000000000000000000000000000000000000000';

/**
 * The Courier's window.
 *
 * A parcel office, so the centre holds a package rather than a unit: pick one of your machines and
 * you see what is actually behind the counter for it, asset by asset. The Courier does not deliver
 * — the collect button is the only thing that moves anything, and what it moves goes into the
 * unit's own wallet rather than yours.
 */
export function DropScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [pick, setPick] = useState<number | undefined>();
  const [, tick] = useState(0);

  // The claim window matters enough to show it ticking rather than as a static timestamp.
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
      {address: addresses.Drop, abi: DropAbi, functionName: 'accumulationProgress', args: [id]},
      {
        address: addresses.RevenueSplitter,
        abi: RevenueSplitterAbi,
        functionName: 'balances',
        args: [addresses.RUN],
      },
      {address: addresses.Drop, abi: DropAbi, functionName: 'buybackPool'},
      {address: addresses.Drop, abi: DropAbi, functionName: 'skippedPool', args: [id]},
      {address: addresses.Augments, abi: AugmentsAbi, functionName: 'augmentCount'},
    ],
    query: {enabled: id > 0n},
  });

  const round = data?.[0]?.result as readonly bigint[] | undefined;
  const progress = data?.[1]?.result as readonly bigint[] | undefined;
  const splits = data?.[2]?.result as readonly bigint[] | undefined;
  const buyback = data?.[3]?.result as bigint | undefined;
  const skipped = data?.[4]?.result as bigint | undefined;
  const catalogSize = Number((data?.[5]?.result as bigint | undefined) ?? 0n);

  const phase = round ? Number(round[6]) : 0;
  const pool = round?.[1];
  const totalWeight = round?.[2];
  const deadline = Number(round?.[5] ?? 0n);
  const waiting = splits?.[0] ?? 0n;
  const now = Math.floor(Date.now() / 1000);
  const accDone = progress ? progress[0] > progress[1] : false;

  const selected = pick ?? owned[0];

  return (
    <>
      <Package
        dropId={id}
        tokenId={selected}
        phase={phase}
        deadline={deadline}
        now={now}
        onSay={onSay}
      />

      <div className="shop-menu">
        <div className="between" style={{marginBottom: 10}}>
          <h3 style={{margin: 0}}>The Window</h3>
          <span className="tag">
            drop #{id.toString()} · {PHASE[phase]}
          </span>
        </div>

        {/* What is behind the counter this week */}
        <div className="kv-grid">
          <div className="kv">
            <span className="kv-k">committed</span>
            <span className="kv-v red">{fmt(pool, 18, 0)} $RUN</span>
          </div>
          <div className="kv">
            <span className="kv-k">eligible weight</span>
            <span className="kv-v">{fmtWeight(totalWeight)}</span>
          </div>
          <div className="kv">
            <span className="kv-k">window closes</span>
            <span className="kv-v">{deadline > now ? countdown(deadline - now) : 'closed'}</span>
          </div>
          <div className="kv">
            <span className="kv-k">buyback pool</span>
            <span className="kv-v">{fmt(buyback, 18, 0)}</span>
          </div>
        </div>

        <h3 style={{margin: '14px 0 8px'}}>Your units</h3>
        {owned.length === 0 ? (
          <div className="faint" style={{fontSize: 12}}>
            Nothing of yours is behind the counter.
          </div>
        ) : (
          <div
            className="grid"
            style={{gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 6}}
          >
            {owned.map((u) => (
              <PackageCard
                key={u}
                dropId={id}
                tokenId={u}
                selected={selected === u}
                onPick={() => setPick(u)}
              />
            ))}
          </div>
        )}

        {/* Anyone can fire a Drop. Weights are read off the machines, never supplied — so whoever
            runs these steps chooses when it happens and never who earns from it. */}
        <h3 style={{margin: '14px 0 8px'}}>Fire a Drop</h3>
        <div className="steps">
          <button
            className={`step ${phase === 0 || phase === 3 ? 'next' : 'done'}`}
            disabled={busy || waiting === 0n || phase === 1}
            onMouseEnter={() => onSay(line('drop', 'enter'))}
            onClick={() =>
              send('open a Drop', {address: addresses.Drop, abi: DropAbi, functionName: 'openDrop'})
            }
          >
            <span className="step-n">1</span>
            <span>
              open — pull the 60% bucket
              <em>{fmt(waiting, 18, 0)} $RUN waiting</em>
            </span>
          </button>

          <button
            className={`step ${phase === 1 && !accDone ? 'next' : phase > 1 ? 'done' : ''}`}
            disabled={busy || phase !== 1}
            onClick={() =>
              send('weigh the collection', {
                address: addresses.Drop,
                abi: DropAbi,
                functionName: 'accumulate',
                args: [id, 50n],
              })
            }
          >
            <span className="step-n">2</span>
            <span>
              weigh the collection
              <em>{progress ? `${progress[0]} / ${progress[1]}` : '—'}</em>
            </span>
          </button>

          <button
            className={`step ${phase === 1 && accDone ? 'next' : phase > 1 ? 'done' : ''}`}
            disabled={busy || phase !== 1 || !accDone}
            onClick={() =>
              send('finalise the Drop', {
                address: addresses.Drop,
                abi: DropAbi,
                functionName: 'finalize',
                args: [id],
              })
            }
          >
            <span className="step-n">3</span>
            <span>
              buy — one purchase per ticker
              <em>at most {catalogSize || 12} trades, however large the collection</em>
            </span>
          </button>
        </div>

        {(skipped ?? 0n) > 0n && (
          <div className="notice" style={{marginTop: 10, padding: '9px 11px'}}>
            <span style={{fontSize: 11.5}}>
              {fmt(skipped, 18, 0)} $RUN rolled forward — some tickers were not purchasable this
              cycle. It is held, not lost.
            </span>
          </div>
        )}

        <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
          Anything left when the window closes is sold to fund a $RUN buyback: a unit whose operator
          does not show up funds the operators who did.
        </p>
      </div>
    </>
  );
}

/* --------------------------------------------------------------- PACKAGE */

/** The parcel itself — what is actually waiting for one unit, asset by asset. */
function Package({
  dropId,
  tokenId,
  phase,
  deadline,
  now,
  onSay,
}: {
  dropId: bigint;
  tokenId?: number;
  phase: number;
  deadline: number;
  now: number;
  onSay: (s: string) => void;
}) {
  const {send, busy} = useTx();
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

  const closing = deadline > now && deadline - now < 86_400;

  if (tokenId === undefined) {
    return (
      <CentrePanel title="NO PACKAGE" sub="nothing selected">
        <div className="faint" style={{fontSize: 12, textAlign: 'center', marginTop: 40}}>
          Pick one of your units and the Courier will check the shelf.
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
            Already gone into the unit&apos;s own wallet. It travels with the machine if you sell it.
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
        <>
          <div className="lots">
            {lots.map((l) => (
              <Lot key={l.bay} asset={l.asset} amount={l.amount} augmentId={l.augmentId} />
            ))}
          </div>

          <Line
            k="window"
            v={deadline > now ? countdown(deadline - now) : 'closed'}
            tone={closing ? 'sodium' : undefined}
          />

          <button
            className="btn primary"
            style={{width: '100%', marginTop: 10}}
            disabled={busy || phase !== 2}
            onMouseEnter={() => onSay(line('drop', closing ? 'expiring' : 'collect'))}
            onClick={() =>
              send(`collect for #${tokenId}`, {
                address: addresses.Drop,
                abi: DropAbi,
                functionName: 'claim',
                args: [dropId, BigInt(tokenId)],
              })
            }
          >
            {phase === 2 ? 'collect into unit wallet' : 'not ready to collect'}
          </button>
        </>
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

/** A unit card that says at a glance whether there is anything on the shelf for it. */
function PackageCard({
  dropId,
  tokenId,
  selected,
  onPick,
}: {
  dropId: bigint;
  tokenId: number;
  selected: boolean;
  onPick: () => void;
}) {
  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimable', args: [dropId, BigInt(tokenId)]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimed', args: [dropId, BigInt(tokenId)]},
    ],
    query: {enabled: dropId > 0n},
  });

  const amounts = (data?.[0]?.result as readonly [unknown, readonly bigint[]] | undefined)?.[1] ?? [];
  const claimed = data?.[1]?.result as boolean | undefined;
  const lots = amounts.filter((a) => a > 0n).length;

  return (
    <button className={`unit-card ${selected ? 'selected' : ''}`} onClick={onPick}>
      <div className="uid">#{String(tokenId).padStart(4, '0')}</div>
      <div className="umodel">
        {claimed ? 'collected' : lots > 0 ? `${lots} lot${lots === 1 ? '' : 's'}` : 'nothing'}
      </div>
      {!claimed && lots > 0 && <span className="pip" />}
    </button>
  );
}
