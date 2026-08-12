'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {
  AugmentsAbi,
  RipperdocAbi,
  StockRunnerAbi,
  ExpansionModulesAbi,
  AUGAbi,
} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';
import {useOwnedUnits} from '@/components/Inventory';
import {ArtSlot} from '@/components/ArtSlot';

const MAX_UINT = 2n ** 256n - 1n;
const TIER_PRICE = [0n, 100n, 250n, 500n];

type Entry = {id: number; ticker: string; tier: number; loose: bigint};

function useCatalog(): Entry[] {
  const {address} = useAccount();

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

  const {data: balances} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'balanceOfBatch',
    args: [ids.map(() => address!), ids],
    query: {enabled: n > 0 && !!address},
  });

  if (!defs) return [];
  return (defs as readonly {ticker: string; tier: number}[]).map((d, i) => ({
    id: i + 1,
    ticker: d.ticker,
    tier: Number(d.tier),
    loose: (balances as readonly bigint[] | undefined)?.[i] ?? 0n,
  }));
}

export function RipperdocClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();
  const catalog = useCatalog();
  const {ids: owned} = useOwnedUnits();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.AUG, abi: AUGAbi, functionName: 'allowance', args: [address!, addresses.Ripperdoc]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'augCredit', args: [address!]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'totalBurned'},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'totalToReserve'},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'totalSupply'},
      {
        address: addresses.ExpansionModules,
        abi: ExpansionModulesAbi,
        functionName: 'balanceOf',
        args: [address!],
      },
    ],
    query: {enabled: !!address},
  });

  const allowance = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const credit = data?.[1]?.result as bigint | undefined;
  const burned = data?.[2]?.result as bigint | undefined;
  const toReserve = data?.[3]?.result as bigint | undefined;
  const supply = data?.[4]?.result as bigint | undefined;
  const looseModules = (data?.[5]?.result as bigint | undefined) ?? 0n;

  if (!isConnected) return <NotConnected />;
  const approved = allowance >= 10_000n * 10n ** 18n;

  return (
    <>
      {!approved && (
        <div className="notice" style={{marginBottom: 16}}>
          <div className="between">
            <span className="dim">
              The Ripperdoc needs permission to take $AUG before he&apos;ll work on anything.
            </span>
            <button
              className="btn primary"
              disabled={busy}
              onClick={() =>
                send('approve $AUG', {
                  address: addresses.AUG,
                  abi: AUGAbi,
                  functionName: 'approve',
                  args: [addresses.Ripperdoc, MAX_UINT],
                })
              }
            >
              approve $AUG
            </button>
          </div>
        </div>
      )}

      <section className="grid g3" style={{marginBottom: 18}}>
        <div className="panel">
          <Stat k="Your credit" v={`${fmt(credit)} $AUG`} accent sub="from selling Augments back" />
        </div>
        <div className="panel">
          <Stat k="Burned here, lifetime" v={fmt(burned, 18, 0)} sub="gone permanently" />
        </div>
        <div className="panel">
          <Stat k="$AUG in existence" v={fmt(supply, 18, 0)} sub="falls with every purchase" />
        </div>
      </section>

      {/* ------------------------------------------------------- CATALOG */}
      <section className="panel" style={{marginBottom: 18}}>
        <div className="between" style={{marginBottom: 12}}>
          <h2>Fresh stock</h2>
          <span className="faint mono" style={{fontSize: 11}}>
            {catalog.length} Augments · one ticker each
          </span>
        </div>

        <div className="grid g3">
          {catalog.map((a) => (
            <div key={a.id} className="panel" style={{background: 'var(--panel-2)', padding: 12}}>
              <div className="between" style={{marginBottom: 8}}>
                <span className={`tag t${a.tier}`}>T{a.tier}</span>
                {a.loose > 0n && <span className="tag on">{a.loose.toString()} loose</span>}
              </div>
              <ArtSlot label={a.ticker} hint="badge" ratio="1 / 1" />
              <div style={{marginTop: 8, fontSize: 16, fontWeight: 600, letterSpacing: '0.04em'}}>
                {a.ticker}
              </div>
              <div className="dim mono" style={{fontSize: 11}}>
                {TIER_PRICE[a.tier].toString()} $AUG · {a.tier === 1 ? '1.0x' : a.tier === 2 ? '1.25x' : '1.5x'}
              </div>
              <button
                className="btn sm"
                style={{marginTop: 10, width: '100%'}}
                disabled={busy || !approved}
                onClick={() =>
                  send(`buy ${a.ticker}`, {
                    address: addresses.Ripperdoc,
                    abi: RipperdocAbi,
                    functionName: 'buyAugment',
                    args: [BigInt(a.id), 1n],
                  })
                }
              >
                buy loose
              </button>
            </div>
          ))}

          <div className="panel" style={{background: 'var(--panel-2)', padding: 12}}>
            <div className="between" style={{marginBottom: 8}}>
              <span className="tag">MODULE</span>
              {looseModules > 0n && <span className="tag on">{looseModules.toString()} loose</span>}
            </div>
            <ArtSlot label="MODULE" hint="expansion" ratio="1 / 1" />
            <div style={{marginTop: 8, fontSize: 16, fontWeight: 600}}>Expansion Module</div>
            <div className="dim mono" style={{fontSize: 11}}>
              500 $AUG · opens one bay
            </div>
            <button
              className="btn sm"
              style={{marginTop: 10, width: '100%'}}
              disabled={busy || !approved}
              onClick={() =>
                send('buy Expansion Module', {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: 'buyModule',
                  args: [1n],
                })
              }
            >
              buy loose
            </button>
          </div>
        </div>

        <Rule>
          Half of every payment burns permanently; half funds the protocol reserve. Tier buys weight
          and is deliberately worse per dollar — a tier-3 costs 3.3× a tier-1 for 1.5× the weight,
          which is correct only once your bays run out. Fill spare bays with tier 1 first.
        </Rule>
      </section>

      {/* --------------------------------------------------------- BENCH */}
      <section>
        <h2 style={{marginBottom: 12}}>The bench</h2>
        {owned.length === 0 ? (
          <div className="panel dim">
            No units to work on. Activate one at the Black Market first.
          </div>
        ) : (
          owned.map((id) => <UnitBench key={id} tokenId={id} catalog={catalog} approved={approved} />)
        )}
      </section>
    </>
  );
}

function UnitBench({
  tokenId,
  catalog,
  approved,
}: {
  tokenId: number;
  catalog: Entry[];
  approved: boolean;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const id = BigInt(tokenId);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'bayCountOf', args: [id]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'unitWeight', args: [id]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'calibrationCountOf', args: [id]},
      {
        address: addresses.ExpansionModules,
        abi: ExpansionModulesAbi,
        functionName: 'balanceOf',
        args: [address!],
      },
    ],
  });

  const bays = Number((data?.[0]?.result as number | undefined) ?? 0);
  const weight = data?.[1]?.result as bigint | undefined;
  const calibrations = Number((data?.[2]?.result as number | undefined) ?? 0);
  const looseModules = (data?.[3]?.result as bigint | undefined) ?? 0n;

  return (
    <div className="panel" style={{marginBottom: 12}}>
      <div className="between" style={{marginBottom: 10}}>
        <div>
          <strong className="mono">#{String(tokenId).padStart(4, '0')}</strong>{' '}
          <span className="tag">{bays} / 3 bays</span>{' '}
          <span className="tag">{calibrations} calibrations</span>
        </div>
        <span className="mono" style={{color: 'var(--chrome)'}}>
          {fmtWeight(weight)}
        </span>
      </div>

      <div className="grid g3">
        {Array.from({length: bays}, (_, i) => (
          <BayBench key={i} tokenId={id} bayIndex={i} catalog={catalog} approved={approved} />
        ))}
      </div>

      <div className="row" style={{marginTop: 12}}>
        <button
          className="btn sm"
          disabled={busy || bays >= 3 || !approved}
          onClick={() =>
            send(`install a bay on #${tokenId}`, {
              address: addresses.Ripperdoc,
              abi: RipperdocAbi,
              functionName: looseModules > 0n ? 'installModule' : 'buyAndInstallModule',
              args: [id],
            })
          }
        >
          {bays >= 3
            ? 'three bays — ceiling reached'
            : looseModules > 0n
              ? 'install a module you hold'
              : 'buy + install module — 500 $AUG'}
        </button>
        <button
          className="btn sm"
          disabled={busy || !approved}
          onClick={() =>
            send(`calibrate #${tokenId}`, {
              address: addresses.Ripperdoc,
              abi: RipperdocAbi,
              functionName: 'calibrate',
              args: [id],
            })
          }
        >
          calibrate — 5 $AUG
        </button>
        <span className="faint" style={{fontSize: 11}}>
          one per unit per day · +0.003x · skipping never penalises
        </span>
      </div>
    </div>
  );
}

function BayBench({
  tokenId,
  bayIndex,
  catalog,
  approved,
}: {
  tokenId: bigint;
  bayIndex: number;
  catalog: Entry[];
  approved: boolean;
}) {
  const {send, busy} = useTx();
  const [pick, setPick] = useState(1);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'getBay', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'tenureCycles', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'isBayEligible', args: [tokenId, bayIndex]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'isBayUnlocked', args: [tokenId, bayIndex]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'bayWeight', args: [tokenId, bayIndex]},
    ],
  });

  const bay = data?.[0]?.result as {augmentId: bigint; tier: number} | undefined;
  const tenure = data?.[1]?.result as bigint | undefined;
  const eligible = data?.[2]?.result as boolean | undefined;
  const unlocked = data?.[3]?.result as boolean | undefined;
  const weight = data?.[4]?.result as bigint | undefined;

  const occupied = !!bay && bay.augmentId > 0n;
  const seated = occupied ? catalog.find((c) => BigInt(c.id) === bay!.augmentId) : undefined;
  const picked = catalog.find((c) => c.id === pick);

  const resale = occupied ? Number(TIER_PRICE[bay!.tier]) / 2 : 0;
  const swapNet = picked ? Math.max(0, Number(TIER_PRICE[picked.tier]) - resale) : 0;

  return (
    <div className="panel" style={{background: 'var(--panel-2)', padding: 12}}>
      <div className="between" style={{marginBottom: 8}}>
        <span className="dim mono" style={{fontSize: 11}}>
          BAY {bayIndex}
        </span>
        <div className="row" style={{gap: 4}}>
          {occupied && <span className={`tag t${bay!.tier}`}>T{bay!.tier}</span>}
          {!unlocked && <span className="tag off">locked</span>}
        </div>
      </div>

      {occupied ? (
        <>
          <div style={{fontSize: 15, fontWeight: 600}}>{seated?.ticker ?? '···'}</div>
          <div className="dim mono" style={{fontSize: 11}}>
            tenure {tenure?.toString() ?? '0'}/8 · {fmtWeight(weight)}
          </div>
          <span className={`tag ${eligible ? 'on' : 'warn'}`} style={{marginTop: 6}}>
            {eligible ? 'earning' : 'seasoning'}
          </span>
        </>
      ) : (
        <div className="dim" style={{fontSize: 12}}>
          empty
        </div>
      )}

      <select
        value={pick}
        onChange={(e) => setPick(Number(e.target.value))}
        style={{width: '100%', marginTop: 10, fontSize: 11}}
      >
        {catalog.map((c) => (
          <option key={c.id} value={c.id}>
            {c.ticker} T{c.tier}
            {c.loose > 0n ? ` · ${c.loose} loose` : ''}
          </option>
        ))}
      </select>

      <div className="row" style={{marginTop: 8, gap: 6}}>
        {!occupied ? (
          <button
            className="btn sm"
            disabled={busy || !unlocked || !approved}
            onClick={() =>
              send(`seat ${picked?.ticker}`, {
                address: addresses.Ripperdoc,
                abi: RipperdocAbi,
                functionName: (picked?.loose ?? 0n) > 0n ? 'seatAugment' : 'buyAndSeatAugment',
                args: [tokenId, bayIndex, BigInt(pick)],
              })
            }
          >
            {(picked?.loose ?? 0n) > 0n
              ? 'seat'
              : `buy + seat · ${picked ? TIER_PRICE[picked.tier].toString() : 0}`}
          </button>
        ) : (
          <>
            <button
              className="btn sm"
              disabled={busy || !unlocked || !approved}
              onClick={() =>
                send(`swap to ${picked?.ticker}`, {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: 'swapAugment',
                  args: [tokenId, bayIndex, BigInt(pick)],
                })
              }
            >
              swap · {swapNet}
            </button>
            <button
              className="btn sm ghost"
              disabled={busy || !unlocked}
              onClick={() =>
                send('sell back', {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: 'sellBackAugment',
                  args: [tokenId, bayIndex],
                })
              }
            >
              sell +{resale}
            </button>
          </>
        )}
      </div>

      {!unlocked && (
        <div className="faint" style={{fontSize: 10.5, marginTop: 6}}>
          Changed this cycle. Unlocks at the next boundary.
        </div>
      )}
      {occupied && (
        <div className="faint" style={{fontSize: 10.5, marginTop: 6}}>
          Swapping resets tenure to zero.
        </div>
      )}
    </div>
  );
}
