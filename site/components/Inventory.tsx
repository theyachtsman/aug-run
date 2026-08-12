'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {EXPLORER} from '@/lib/chain';
import {
  StockRunnerAbi,
  RipperdocAbi,
  AugmentsAbi,
  ExpansionModulesAbi,
} from '@/lib/generated/abis';
import {fmt, fmtWeight, shortAddr, tierLabel} from '@/lib/format';
import {ArtSlot, modelName} from './ArtSlot';

/** Scan 1..totalMinted for units held by the connected wallet. Batched through Multicall3. */
export function useOwnedUnits() {
  const {address} = useAccount();

  const {data: total} = useReadContract({
    address: addresses.StockRunner,
    abi: StockRunnerAbi,
    functionName: 'totalMinted',
  });

  const n = Number(total ?? 0n);
  const ids = Array.from({length: n}, (_, i) => i + 1);

  const {data, isLoading} = useReadContracts({
    contracts: ids.map((id) => ({
      address: addresses.StockRunner,
      abi: StockRunnerAbi,
      functionName: 'ownerOf' as const,
      args: [BigInt(id)],
    })),
    query: {enabled: n > 0 && !!address},
  });

  const owned = ids.filter(
    (_, i) =>
      data?.[i]?.status === 'success' &&
      (data[i].result as string)?.toLowerCase() === address?.toLowerCase(),
  );

  return {ids: owned, loading: isLoading, collectionSize: n};
}

/**
 * The operator's Stock//Runner inventory — every unit they hold, inspectable without visiting a
 * vendor. Loadout, tenure, weight and the unit's own wallet in one place.
 */
export function Inventory({onClose}: {onClose: () => void}) {
  const {ids, loading, collectionSize} = useOwnedUnits();
  const [selected, setSelected] = useState<number | null>(null);

  return (
    <>
      <div className="scrim" onClick={onClose} />
      <aside className="drawer">
        <div className="drawer-head">
          <div>
            <h2>Stock//Runner Inventory</h2>
            <div className="dim mono" style={{fontSize: 11}}>
              {ids.length} held · {collectionSize}/333 activated
            </div>
          </div>
          <button className="btn sm ghost" onClick={onClose}>
            close
          </button>
        </div>

        <div className="drawer-body">
          {loading && <div className="dim">reading the collection…</div>}

          {!loading && ids.length === 0 && (
            <div className="panel">
              <h3>No units</h3>
              <p className="dim" style={{marginBottom: 0}}>
                You don&apos;t hold a Stock//Runner yet. A blank unit activates at the Black Market for
                1,000,000 $RUN — what it becomes is entirely a function of what you install.
              </p>
            </div>
          )}

          {selected === null &&
            ids.map((id) => <UnitRow key={id} tokenId={id} onOpen={() => setSelected(id)} />)}

          {selected !== null && (
            <UnitDossier tokenId={selected} onBack={() => setSelected(null)} />
          )}
        </div>
      </aside>
    </>
  );
}

function UnitRow({tokenId, onOpen}: {tokenId: number; onOpen: () => void}) {
  const id = BigInt(tokenId);
  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'modelOf', args: [id]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'bayCountOf', args: [id]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'unitWeight', args: [id]},
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'unitEligibleWeight',
        args: [id],
      },
    ],
  });

  const model = data?.[0]?.result as number | undefined;
  const bays = Number((data?.[1]?.result as number | undefined) ?? 0);
  const weight = data?.[2]?.result as bigint | undefined;
  const eligible = data?.[3]?.result as bigint | undefined;

  return (
    <button
      onClick={onOpen}
      className="panel"
      style={{
        width: '100%',
        textAlign: 'left',
        marginBottom: 10,
        cursor: 'pointer',
        display: 'flex',
        gap: 14,
        alignItems: 'center',
      }}
    >
      <ArtSlot label={modelName(model)} ratio="1 / 1" className="" />
      <div style={{flex: 1, minWidth: 0}}>
        <div className="between">
          <strong className="mono">#{String(tokenId).padStart(4, '0')}</strong>
          <span className="mono" style={{color: 'var(--chrome)'}}>
            {fmtWeight(weight)}
          </span>
        </div>
        <div className="dim" style={{fontSize: 12}}>
          {modelName(model)}
        </div>
        <div className="row" style={{marginTop: 6}}>
          <span className="tag">
            {bays} bay{bays === 1 ? '' : 's'}
          </span>
          <span className={`tag ${(eligible ?? 0n) > 0n ? 'on' : ''}`}>
            {(eligible ?? 0n) > 0n ? 'earning' : 'idle'}
          </span>
        </div>
      </div>
    </button>
  );
}

/** The full record for one unit: loadout, tenure, weight, wallet. */
function UnitDossier({tokenId, onBack}: {tokenId: number; onBack: () => void}) {
  const id = BigInt(tokenId);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'modelOf', args: [id]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'bayCountOf', args: [id]},
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'tokenBoundAccount',
        args: [id],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'calibrationCountOf',
        args: [id],
      },
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'unitWeight', args: [id]},
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'unitEligibleWeight',
        args: [id],
      },
      {
        address: addresses.ExpansionModules,
        abi: ExpansionModulesAbi,
        functionName: 'MODULE_ID',
      },
    ],
  });

  const model = data?.[0]?.result as number | undefined;
  const bays = Number((data?.[1]?.result as number | undefined) ?? 0);
  const tba = data?.[2]?.result as string | undefined;
  const calibrations = Number((data?.[3]?.result as number | undefined) ?? 0);
  const weight = data?.[4]?.result as bigint | undefined;
  const eligible = data?.[5]?.result as bigint | undefined;

  return (
    <div>
      <button className="btn sm ghost" onClick={onBack} style={{marginBottom: 14}}>
        ← all units
      </button>

      <div className="panel" style={{marginBottom: 14}}>
        <div className="row" style={{alignItems: 'flex-start', gap: 16}}>
          <ArtSlot
            label={modelName(model)}
            hint="unit render"
            ratio="3 / 4"
            className=""
          />
          <div style={{flex: 1, minWidth: 0}}>
            <h2 style={{fontSize: 20}}>#{String(tokenId).padStart(4, '0')}</h2>
            <div className="dim" style={{fontSize: 12, marginBottom: 10}}>
              {modelName(model)} · one of {model !== undefined && model < 3 ? 31 : 30} in this line
            </div>

            <Stat k="Unit weight" v={fmtWeight(weight)} accent />
            <Stat k="Earning this cycle" v={fmtWeight(eligible)} />
            <Stat k="Bays" v={`${bays} / 3`} />
            <Stat k="Calibrations" v={String(calibrations)} />
            <Stat
              k="Wallet"
              v={
                <a href={`${EXPLORER}/address/${tba}`} target="_blank" rel="noreferrer">
                  {shortAddr(tba)}
                </a>
              }
            />
          </div>
        </div>
      </div>

      <h3 style={{marginBottom: 8}}>Loadout</h3>
      <div className="grid" style={{gap: 10, marginBottom: 16}}>
        {Array.from({length: Math.max(bays, 1)}, (_, i) => (
          <BayCard key={i} tokenId={id} bayIndex={i} />
        ))}
        {Array.from({length: 3 - bays}, (_, i) => (
          <div key={`locked-${i}`} className="panel" style={{opacity: 0.45}}>
            <div className="between">
              <span className="dim mono" style={{fontSize: 12}}>
                BAY {bays + i}
              </span>
              <span className="tag">locked</span>
            </div>
            <div className="dim" style={{fontSize: 12, marginTop: 6}}>
              Install an Expansion Module at the Ripperdoc to open this bay.
            </div>
          </div>
        ))}
      </div>

      <h3 style={{marginBottom: 8}}>Portfolio</h3>
      <div className="panel">
        <p className="dim" style={{fontSize: 12.5, margin: 0}}>
          Real-world assets delivered by the Drop live in this unit&apos;s own wallet, so its position
          and PnL belong to the machine rather than to you — and travel with it when it sells.
        </p>
        <div className="notice" style={{marginTop: 12}}>
          <strong style={{color: 'var(--sodium)'}}>Awaiting price feeds.</strong>{' '}
          <span className="dim">
            Holdings and PnL need Chainlink Data Feeds, which are live on Robinhood Chain mainnet but
            not on testnet. Wired up at mainnet.
          </span>
        </div>
      </div>
    </div>
  );
}

function BayCard({tokenId, bayIndex}: {tokenId: bigint; bayIndex: number}) {
  const {data} = useReadContracts({
    contracts: [
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'getBay',
        args: [tokenId, bayIndex],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'tenureCycles',
        args: [tokenId, bayIndex],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isBayEligible',
        args: [tokenId, bayIndex],
      },
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'bayWeight',
        args: [tokenId, bayIndex],
      },
    ],
  });

  const bay = data?.[0]?.result as {augmentId: bigint; tier: number} | undefined;
  const tenure = data?.[1]?.result as bigint | undefined;
  const eligible = data?.[2]?.result as boolean | undefined;
  const weight = data?.[3]?.result as bigint | undefined;

  const occupied = !!bay && bay.augmentId > 0n;

  const {data: ticker} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'tickerOf',
    args: [bay?.augmentId ?? 0n],
    query: {enabled: occupied},
  });

  return (
    <div className="panel">
      <div className="between">
        <span className="dim mono" style={{fontSize: 12}}>
          BAY {bayIndex}
        </span>
        {occupied ? (
          <span className={`tag t${bay!.tier}`}>{tierLabel(bay!.tier)}</span>
        ) : (
          <span className="tag">empty</span>
        )}
      </div>

      {occupied ? (
        <>
          <div className="row" style={{marginTop: 10, alignItems: 'center', gap: 12}}>
            <ArtSlot label={(ticker as string) ?? '···'} ratio="1 / 1" hint="badge" />
            <div style={{flex: 1}}>
              <div style={{fontSize: 17, fontWeight: 600, letterSpacing: '0.04em'}}>
                {(ticker as string) ?? '···'}
              </div>
              <div className="dim mono" style={{fontSize: 11.5}}>
                tenure {tenure?.toString() ?? '0'}/8
              </div>
              <div className="row" style={{marginTop: 6}}>
                <span className="mono" style={{color: 'var(--chrome)'}}>
                  {fmtWeight(weight)}
                </span>
                <span className={`tag ${eligible ? 'on' : 'warn'}`}>
                  {eligible ? 'earning' : 'seasoning'}
                </span>
              </div>
            </div>
          </div>
          {!eligible && (
            <div className="dim" style={{fontSize: 11.5, marginTop: 8}}>
              Seated mid-cycle — it earns from the next full cycle. Rebinding would reset its tenure.
            </div>
          )}
        </>
      ) : (
        <div className="dim" style={{fontSize: 12, marginTop: 8}}>
          Nothing installed. An Augment seated here binds to this unit permanently.
        </div>
      )}
    </div>
  );
}

function Stat({k, v, accent}: {k: string; v: React.ReactNode; accent?: boolean}) {
  return (
    <div className="between" style={{padding: '3px 0'}}>
      <span className="dim" style={{fontSize: 12}}>
        {k}
      </span>
      <span className="mono" style={{color: accent ? 'var(--chrome)' : undefined}}>
        {v}
      </span>
    </div>
  );
}
