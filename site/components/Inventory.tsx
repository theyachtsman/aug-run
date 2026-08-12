'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {keccak256, stringToHex} from 'viem';
import {addresses} from '@/lib/addresses';
import {EXPLORER} from '@/lib/chain';
import {
  StockRunnerAbi,
  RipperdocAbi,
  AugmentsAbi,
  ExpansionModulesAbi,
  DropAbi,
  MockRwaVenueAbi,
  RUNAbi,
  AUGAbi,
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
  const {address} = useAccount();
  const {ids, loading, collectionSize} = useOwnedUnits();
  const [selected, setSelected] = useState<number | null>(null);

  // Your own wallet, as distinct from your machines'. Keeping both in one drawer makes the split
  // legible: $RUN and $AUG are yours to spend, everything below belongs to a unit.
  const {data: purse} = useReadContracts({
    contracts: [
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'balanceOf', args: [address!]},
    ],
    query: {enabled: !!address},
  });

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

        <div className="purse">
          <div className="purse-cell">
            <span className="purse-k mono">$RUN</span>
            <span className="purse-v mono">{fmt(purse?.[0]?.result as bigint | undefined, 18, 2)}</span>
          </div>
          <div className="purse-cell">
            <span className="purse-k mono">$AUG</span>
            <span className="purse-v mono">{fmt(purse?.[1]?.result as bigint | undefined, 18, 2)}</span>
          </div>
          <div className="purse-cell">
            <span className="purse-k mono">YOUR WALLET</span>
            <span className="purse-v mono dim">{shortAddr(address)}</span>
          </div>
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
      <UnitPortfolio tokenId={id} tba={tba} />
    </div>
  );
}

/**
 * What this unit's own wallet actually holds.
 *
 * The set of assets a unit can hold is bounded by the Augment catalog — the Drop only ever buys a
 * ticker that some bay is running — so the venue is asked for each catalog ticker's ERC-20 and the
 * unit's wallet is read directly. That is the honest source: it reflects the wallet, not a ledger
 * the protocol keeps about the wallet, so assets sent in by any other route show up too.
 *
 * No USD valuation. Pricing needs Chainlink Data Feeds, which are live on Robinhood Chain mainnet
 * but not on testnet — quantities are real now, values arrive with the feeds.
 */
function UnitPortfolio({tokenId, tba}: {tokenId: bigint; tba?: string}) {
  const {data: count} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'augmentCount',
  });
  const n = Number(count ?? 0n);

  const {data: defs} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'catalog',
    query: {enabled: n > 0},
  });

  const {data: venue} = useReadContract({
    address: addresses.Drop,
    abi: DropAbi,
    functionName: 'venue',
  });

  const tickers = ((defs as readonly {ticker: string}[] | undefined) ?? []).map((d) => d.ticker);

  // Drop hashes a ticker as keccak256(bytes(ticker)) — match it exactly or assetFor returns zero.
  const {data: assetData} = useReadContracts({
    contracts: tickers.map((t) => ({
      address: venue as `0x${string}`,
      abi: MockRwaVenueAbi,
      functionName: 'assetFor' as const,
      args: [keccak256(stringToHex(t))],
    })),
    query: {enabled: tickers.length > 0 && !!venue},
  });

  const holdings = tickers
    .map((ticker, i) => ({ticker, asset: assetData?.[i]?.result as `0x${string}` | undefined}))
    .filter(
      (h, i, arr) =>
        !!h.asset &&
        h.asset !== '0x0000000000000000000000000000000000000000' &&
        // One ERC-20 can back several tickers; only read it once.
        arr.findIndex((x) => x.asset === h.asset) === i,
    );

  if (!venue || holdings.length === 0) {
    return (
      <div className="panel">
        <p className="dim" style={{fontSize: 12.5, margin: 0}}>
          Real-world assets delivered by the Drop live in this unit&apos;s own wallet, so its position
          belongs to the machine rather than to you — and travels with it when it sells.
        </p>
        <div className="notice" style={{marginTop: 12}}>
          <span className="dim">No venue is configured yet, so there is nothing to read.</span>
        </div>
      </div>
    );
  }

  return (
    <div className="panel">
      <table>
        <thead>
          <tr>
            <th>asset</th>
            <th style={{textAlign: 'right'}}>held</th>
            <th style={{textAlign: 'right'}}>value</th>
          </tr>
        </thead>
        <tbody>
          {holdings.map((h) => (
            <HoldingRow
              key={h.asset}
              tokenId={tokenId}
              tba={tba}
              asset={h.asset!}
              ticker={h.ticker}
            />
          ))}
        </tbody>
      </table>

      <p className="dim" style={{fontSize: 11.5, marginTop: 12, marginBottom: 0}}>
        Held in the unit&apos;s own wallet <code>{shortAddr(tba)}</code>, not yours. USD valuation
        needs Chainlink Data Feeds — live on Robinhood Chain mainnet, absent on testnet — so
        quantities are real and values arrive with the feeds.
      </p>
    </div>
  );
}

/** One asset line: what the wallet holds, plus any dust the Drop is holding back for it. */
function HoldingRow({
  tokenId,
  tba,
  asset,
  ticker,
}: {
  tokenId: bigint;
  tba?: string;
  asset: `0x${string}`;
  ticker: string;
}) {
  const {data} = useReadContracts({
    contracts: [
      {address: asset, abi: RUNAbi, functionName: 'balanceOf', args: [tba as `0x${string}`]},
      {address: asset, abi: RUNAbi, functionName: 'symbol'},
      {address: asset, abi: RUNAbi, functionName: 'decimals'},
      {address: addresses.Drop, abi: DropAbi, functionName: 'dustCredit', args: [tokenId, asset]},
    ],
    query: {enabled: !!tba},
  });

  const balance = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const symbol = (data?.[1]?.result as string | undefined) ?? ticker;
  const decimals = Number((data?.[2]?.result as number | undefined) ?? 18);
  const dust = (data?.[3]?.result as bigint | undefined) ?? 0n;

  if (balance === 0n && dust === 0n) return null;

  return (
    <tr>
      <td>
        <span className="mono">{symbol}</span>
        <span className="dim" style={{fontSize: 11, marginLeft: 6}}>
          via {ticker}
        </span>
      </td>
      <td style={{textAlign: 'right'}} className="mono">
        {fmt(balance, decimals, 6)}
        {dust > 0n && (
          <div className="dim" style={{fontSize: 10.5}}>
            +{fmt(dust, decimals, 6)} held back as dust
          </div>
        )}
      </td>
      <td style={{textAlign: 'right'}} className="dim">
        —
      </td>
    </tr>
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
