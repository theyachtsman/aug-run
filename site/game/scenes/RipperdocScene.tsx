'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {AugmentsAbi, RipperdocAbi, StockRunnerAbi, AUGAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight} from '@/lib/format';
import {useOwnedUnits} from '@/components/Inventory';
import {useDrag, DropSlot, type DragItem} from '../dnd';
import {line} from '../vendors';
import {hardware} from '../augmentNames';
import {UnitPreview} from '../UnitPreview';
import {modelName} from '@/components/ArtSlot';

const MAX_UINT = 2n ** 256n - 1n;
const PRICE = [0n, 100n, 250n, 500n];

/**
 * The Ripperdoc's bench.
 *
 * Seating is a drag: you pick an Augment off the wall and put it into a bay. That is the one
 * interaction in the protocol that is genuinely physical — the token is burned into the unit and
 * cannot come back out — so making it a deliberate drag rather than a dropdown selection is worth
 * the extra machinery. The Doc comments on what you do, and the rules arrive in his voice.
 */
export function RipperdocScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const {begin} = useDrag();
  const [unitIdx, setUnitIdx] = useState(0);

  const tokenId = owned[unitIdx];

  const {data: count} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'augmentCount',
  });
  const n = Number(count ?? 0n);
  const ids = Array.from({length: n}, (_, i) => BigInt(i + 1));

  const {data: defs} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'catalog',
    query: {enabled: n > 0},
  });

  const {data: bal} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'balanceOfBatch',
    args: [ids.map(() => address!), ids],
    query: {enabled: n > 0 && !!address},
  });

  const {data: unitData} = useReadContracts({
    contracts: [
      {address: addresses.AUG, abi: AUGAbi, functionName: 'allowance', args: [address!, addresses.Ripperdoc]},
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'bayCountOf',
        args: [BigInt(tokenId ?? 0)],
      },
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'unitWeight',
        args: [BigInt(tokenId ?? 0)],
      },
    ],
    query: {enabled: !!address},
  });

  const allowance = (unitData?.[0]?.result as bigint | undefined) ?? 0n;
  const bays = Number((unitData?.[1]?.result as number | undefined) ?? 0);
  const weight = unitData?.[2]?.result as bigint | undefined;
  const approved = allowance >= 10_000n * 10n ** 18n;

  const catalog = ((defs as readonly {ticker: string; tier: number}[] | undefined) ?? []).map(
    (d, i) => ({
      id: i + 1,
      ticker: d.ticker,
      tier: Number(d.tier),
      loose: (bal as readonly bigint[] | undefined)?.[i] ?? 0n,
    }),
  );

  const seat = (item: DragItem, bayIndex: number) => {
    if (tokenId === undefined) return;
    const entry = catalog.find((c) => c.id === item.id);
    onSay(line('ripperdoc', 'seated'));
    send(`seat ${item.label} in bay ${bayIndex}`, {
      address: addresses.Ripperdoc,
      abi: RipperdocAbi,
      functionName: (entry?.loose ?? 0n) > 0n ? 'seatAugment' : 'buyAndSeatAugment',
      args: [BigInt(tokenId), bayIndex, BigInt(item.id)],
    });
  };

  return (
    <>
      <UnitPreview
        tokenId={tokenId}
        caption={tokenId === undefined ? 'Nothing on the bench yet.' : 'On the bench'}
      />

    <div className="shop-menu">
      <div className="between" style={{marginBottom: 10}}>
        <h3 style={{margin: 0}}>The Bench</h3>
      </div>

      {owned.length > 1 && (
        <div
          className="grid"
          style={{gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 6, marginBottom: 12}}
        >
          {owned.map((id, i) => (
            <button
              key={id}
              className={`unit-card ${i === unitIdx ? 'selected' : ''}`}
              onClick={() => setUnitIdx(i)}
            >
              <div className="uid">#{String(id).padStart(4, '0')}</div>
              <div className="umodel">on the bench</div>
            </button>
          ))}
        </div>
      )}

      {!approved ? (
        <button
          className="btn primary"
          style={{width: '100%'}}
          disabled={busy}
          onClick={() => {
            onSay(line('ripperdoc', 'noAug'));
            send('approve $AUG', {
              address: addresses.AUG,
              abi: AUGAbi,
              functionName: 'approve',
              args: [addresses.Ripperdoc, MAX_UINT],
            });
          }}
        >
          let him take $AUG
        </button>
      ) : tokenId === undefined ? (
        <div className="dim" style={{fontSize: 12}}>
          Nothing on the bench. Get a unit from the Fence first.
        </div>
      ) : (
        <>
          <div className="between" style={{marginBottom: 8}}>
            <span className="mono" style={{fontSize: 12}}>
              #{String(tokenId).padStart(4, '0')}
            </span>
            <span className="mono" style={{color: 'var(--red)'}}>
              {fmtWeight(weight)}
            </span>
          </div>

          {/* Bays — the drop targets */}
          <div className="grid" style={{gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, marginBottom: 14}}>
            {[0, 1, 2].map((b) => (
              <BaySlot
                key={b}
                tokenId={BigInt(tokenId)}
                bayIndex={b}
                open={b < bays}
                catalog={catalog}
                onSeat={seat}
                onSay={onSay}
              />
            ))}
          </div>

          {/* The wall — draggable stock */}
          <h3 style={{marginBottom: 8}}>On the wall</h3>
          <div className="inv-grid">
            {catalog.map((c) => (
              <div
                key={c.id}
                className={`item-chip hw t${c.tier}`}
                onPointerDown={(e) =>
                  begin({kind: 'augment', id: c.id, label: c.ticker, tier: c.tier}, e)
                }
                onPointerEnter={() => onSay(hardware(c.ticker).flavour)}
                title={`${hardware(c.ticker).name} · tier ${c.tier} · ${PRICE[c.tier]} $AUG`}
              >
                <div>
                  <div className="hwslot mono">{hardware(c.ticker).slot}</div>
                  <div style={{fontSize: 13, fontWeight: 600}}>{c.ticker}</div>
                  <div className="hwname">{hardware(c.ticker).name}</div>
                  <div className="faint" style={{fontSize: 9.5, marginTop: 2}}>
                    T{c.tier} · {PRICE[c.tier].toString()}
                  </div>
                </div>
                {c.loose > 0n && <span className="qty">×{c.loose.toString()}</span>}
              </div>
            ))}
          </div>

          <div className="row" style={{marginTop: 12}}>
            <button
              className="btn sm"
              disabled={busy || bays >= 3}
              onClick={() => {
                onSay(line('ripperdoc', 'tierAdvice'));
                send('install a bay', {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: 'buyAndInstallModule',
                  args: [BigInt(tokenId)],
                });
              }}
            >
              {bays >= 3 ? 'three bays — that is the ceiling' : 'open another bay · 500'}
            </button>
            <button
              className="btn sm"
              disabled={busy}
              onClick={() => {
                onSay(line('ripperdoc', 'calibrate'));
                send('calibrate', {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: 'calibrate',
                  args: [BigInt(tokenId)],
                });
              }}
            >
              calibrate · 5
            </button>
          </div>

          <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
            Drag hardware off the wall and into a bay to seat it.
          </p>
        </>
      )}
    </div>
    </>
  );
}

function BaySlot({
  tokenId,
  bayIndex,
  open,
  catalog,
  onSeat,
  onSay,
}: {
  tokenId: bigint;
  bayIndex: number;
  open: boolean;
  catalog: {id: number; ticker: string; tier: number; loose: bigint}[];
  onSeat: (i: DragItem, bay: number) => void;
  onSay: (s: string) => void;
}) {
  const {send, busy} = useTx();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'getBay', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'tenureCycles', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'isBayUnlocked', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'isBayEligible', args: [tokenId, bayIndex]},
    ],
    query: {enabled: open},
  });

  const bay = data?.[0]?.result as {augmentId: bigint; tier: number} | undefined;
  const tenure = data?.[1]?.result as bigint | undefined;
  const unlocked = (data?.[2]?.result as boolean | undefined) ?? true;
  const eligible = data?.[3]?.result as boolean | undefined;

  const occupied = !!bay && bay.augmentId > 0n;
  const seated = occupied ? catalog.find((c) => BigInt(c.id) === bay!.augmentId) : undefined;

  if (!open) {
    return (
      <div className="bay-slot locked">
        <div className="faint mono" style={{fontSize: 10}}>
          BAY {bayIndex}
        </div>
        <div className="faint" style={{fontSize: 11, marginTop: 6}}>
          not fitted
        </div>
      </div>
    );
  }

  return (
    <DropSlot
      className={`bay-slot ${occupied ? 'filled' : ''} ${!unlocked ? 'locked' : ''}`}
      accept={() => unlocked}
      onDrop={(item) => {
        if (!unlocked) {
          onSay(line('ripperdoc', 'lockedBay'));
          return;
        }
        if (occupied) {
          onSay(line('ripperdoc', 'swapWarning'));
          send(`swap bay ${bayIndex}`, {
            address: addresses.Ripperdoc,
            abi: RipperdocAbi,
            functionName: 'swapAugment',
            args: [tokenId, bayIndex, BigInt(item.id)],
          });
          return;
        }
        onSeat(item, bayIndex);
      }}
    >
      <div className="between">
        <span className="faint mono" style={{fontSize: 10}}>
          BAY {bayIndex}
        </span>
        {!unlocked && <span className="tag off">locked</span>}
      </div>

      {occupied ? (
        <div style={{marginTop: 6}}>
          <div className={`item-chip t${bay!.tier}`} style={{height: 58, cursor: 'default'}}>
            <div>
              <div style={{fontSize: 12, fontWeight: 600}}>{seated?.ticker ?? '···'}</div>
              <div className="hwname">{seated ? hardware(seated.ticker).name : ''}</div>
            </div>
          </div>
          <div className="faint mono" style={{fontSize: 10, marginTop: 4}}>
            tenure {tenure?.toString() ?? '0'}/8 · {eligible ? 'earning' : 'seasoning'}
          </div>
          <button
            className="btn sm ghost"
            style={{marginTop: 6, width: '100%', fontSize: 10}}
            disabled={busy || !unlocked}
            onClick={() =>
              send('sell it back', {
                address: addresses.Ripperdoc,
                abi: RipperdocAbi,
                functionName: 'sellBackAugment',
                args: [tokenId, bayIndex],
              })
            }
          >
            pull it out
          </button>
        </div>
      ) : (
        <div className="faint" style={{fontSize: 11, marginTop: 14, textAlign: 'center'}}>
          drop hardware here
        </div>
      )}
    </DropSlot>
  );
}
