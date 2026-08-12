import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses, EXPLORER} from '../addresses';
import {StockRunnerAbi, RipperdocAbi, ExpansionModulesAbi, AUGAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt, fmtWeight, shortAddr} from '../lib/format';
import {useCatalog, type CatalogEntry} from './ShopPanel';

/** Scan 1..totalMinted for tokens owned by the connected wallet. Batched via Multicall3. */
export function useOwnedUnits(): {ids: number[]; loading: boolean} {
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

  return {ids: owned, loading: isLoading};
}

export function UnitsPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids, loading} = useOwnedUnits();
  const catalog = useCatalog();

  // Every action in this panel spends $AUG through the Ripperdoc, so it needs an allowance. The
  // approve control lives here as well as in the shop — otherwise these buttons just revert with
  // nothing on screen explaining why. Note approvals do NOT survive a Ripperdoc redeploy.
  const {data: allowance} = useReadContract({
    address: addresses.AUG,
    abi: AUGAbi,
    functionName: 'allowance',
    args: [address!, addresses.Ripperdoc],
    query: {enabled: !!address},
  });

  const augApproved = (allowance ?? 0n) >= 1000n * 10n ** 18n;

  return (
    <div className="panel">
      <h2>Your Stock//Runners</h2>

      {!augApproved && (
        <div className="panel" style={{borderColor: 'var(--warn)', marginBottom: 12}}>
          <div className="spread">
            <span style={{color: 'var(--warn)'}}>
              $AUG is not approved for the Ripperdoc — installing bays, seating and calibrating will
              all revert until it is.
            </span>
            <button
              className="primary"
              disabled={busy}
              onClick={() =>
                send('approve $AUG for the Ripperdoc', {
                  address: addresses.AUG,
                  abi: AUGAbi,
                  functionName: 'approve',
                  args: [addresses.Ripperdoc, 2n ** 256n - 1n],
                })
              }
            >
              approve $AUG
            </button>
          </div>
        </div>
      )}

      {loading && <div className="dim">scanning…</div>}
      {!loading && ids.length === 0 && (
        <div className="dim">
          None yet. Mint one above — you become its operator and it starts blank, with one bay.
        </div>
      )}
      {ids.map((id) => (
        <Unit key={id} tokenId={id} catalog={catalog} augApproved={augApproved} />
      ))}
    </div>
  );
}

function Unit({
  tokenId,
  catalog,
  augApproved,
}: {
  tokenId: number;
  catalog: CatalogEntry[];
  augApproved: boolean;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
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
        functionName: 'balanceOf',
        args: [address!],
      },
    ],
  });

  const model = data?.[0]?.result as number | undefined;
  const bayCount = Number((data?.[1]?.result as number | undefined) ?? 0);
  const tba = data?.[2]?.result as string | undefined;
  const calibrations = Number((data?.[3]?.result as number | undefined) ?? 0);
  const unitWeight = data?.[4]?.result as bigint | undefined;
  const eligibleWeight = data?.[5]?.result as bigint | undefined;
  const looseModules = (data?.[6]?.result as bigint | undefined) ?? 0n;

  return (
    <div className="unit">
      <div className="spread">
        <div>
          <strong style={{fontSize: 15}}>Stock//Runner #{tokenId}</strong>{' '}
          <span className="tag">model {model ?? '—'}</span>{' '}
          <span className="tag">
            {bayCount} bay{bayCount === 1 ? '' : 's'}
          </span>{' '}
          <span className="tag">{calibrations} calibrations</span>
        </div>
        <div className="mono">
          weight <strong>{fmtWeight(unitWeight)}</strong>{' '}
          <span className="dim">(eligible {fmtWeight(eligibleWeight)})</span>
        </div>
      </div>

      <div className="note">
        wallet (ERC-6551):{' '}
        <a href={`${EXPLORER}/address/${tba}`} target="_blank" rel="noreferrer">
          {shortAddr(tba)}
        </a>
      </div>

      <table style={{marginTop: 8}}>
        <thead>
          <tr>
            <th>bay</th>
            <th>seated</th>
            <th>tier</th>
            <th>tenure</th>
            <th>weight</th>
            <th>state</th>
            <th>actions</th>
          </tr>
        </thead>
        <tbody>
          {Array.from({length: bayCount}, (_, i) => (
            <Bay key={i} tokenId={id} bayIndex={i} catalog={catalog} augApproved={augApproved} />
          ))}
        </tbody>
      </table>

      <div className="row" style={{marginTop: 10}}>
        <button
          disabled={busy || bayCount >= 3 || !augApproved}
          onClick={() =>
            send(`install module on #${tokenId}`, {
              address: addresses.Ripperdoc,
              abi: RipperdocAbi,
              functionName: looseModules > 0n ? 'installModule' : 'buyAndInstallModule',
              args: [id],
            })
          }
        >
          {bayCount >= 3
            ? 'bay ceiling reached (3)'
            : looseModules > 0n
              ? 'install module (you hold one)'
              : 'buy + install module — 500 $AUG'}
        </button>
        <button
          disabled={busy || !augApproved}
          onClick={() =>
            send(`calibrate #${tokenId}`, {
              address: addresses.Ripperdoc,
              abi: RipperdocAbi,
              functionName: 'calibrate',
              args: [id],
            })
          }
        >
          calibrate — 5 $AUG (+0.003x)
        </button>
      </div>
    </div>
  );
}

function Bay({
  tokenId,
  bayIndex,
  catalog,
  augApproved,
}: {
  tokenId: bigint;
  bayIndex: number;
  catalog: CatalogEntry[];
  augApproved: boolean;
}) {
  const {send, busy} = useTx();
  const [pick, setPick] = useState<number>(1);
  const bi = bayIndex;

  const {data} = useReadContracts({
    contracts: [
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'getBay',
        args: [tokenId, bi],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'tenureCycles',
        args: [tokenId, bi],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isBayEligible',
        args: [tokenId, bi],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isBayUnlocked',
        args: [tokenId, bi],
      },
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'bayWeight',
        args: [tokenId, bi],
      },
    ],
  });

  const bay = data?.[0]?.result as
    | {augmentId: bigint; tier: number; seatedAtCycle: bigint; everChanged: boolean}
    | undefined;
  const tenure = data?.[1]?.result as bigint | undefined;
  const eligible = data?.[2]?.result as boolean | undefined;
  const unlocked = data?.[3]?.result as boolean | undefined;
  const weight = data?.[4]?.result as bigint | undefined;

  const occupied = !!bay && bay.augmentId > 0n;
  const seatedEntry = occupied ? catalog.find((c) => BigInt(c.id) === bay!.augmentId) : undefined;
  const picked = catalog.find((c) => c.id === pick);

  const resale = occupied ? (bay!.tier === 1 ? 50 : bay!.tier === 2 ? 125 : 250) : 0;
  const swapNet = picked ? Math.max(0, Number(picked.price / 10n ** 18n) - resale) : 0;

  return (
    <tr>
      <td className="mono dim">{bayIndex}</td>
      <td>{occupied ? <strong>{seatedEntry?.ticker ?? `#${bay!.augmentId}`}</strong> : <span className="dim">empty</span>}</td>
      <td>{occupied ? <span className={`tag t${bay!.tier}`}>T{bay!.tier}</span> : '—'}</td>
      <td className="mono">{occupied ? `${tenure?.toString() ?? '0'}/8` : '—'}</td>
      <td className="mono">{occupied ? fmtWeight(weight) : '—'}</td>
      <td>
        {occupied && (eligible ? <span className="tag eligible">earning</span> : <span className="tag">seasoning</span>)}{' '}
        {!unlocked && <span className="tag locked">locked</span>}
      </td>
      <td>
        <div className="row">
          <select value={pick} onChange={(e) => setPick(Number(e.target.value))}>
            {catalog.map((c) => (
              <option key={c.id} value={c.id}>
                {c.ticker} T{c.tier} · {Number(c.price / 10n ** 18n)}
                {c.loose > 0n ? ` · ${c.loose} loose` : ''}
              </option>
            ))}
          </select>

          {!occupied && (
            <button
              disabled={busy || !augApproved}
              onClick={() =>
                send(`seat ${picked?.ticker} in bay ${bayIndex}`, {
                  address: addresses.Ripperdoc,
                  abi: RipperdocAbi,
                  functionName: (picked?.loose ?? 0n) > 0n ? 'seatAugment' : 'buyAndSeatAugment',
                  args: [tokenId, bi, BigInt(pick)],
                })
              }
            >
              {(picked?.loose ?? 0n) > 0n
                ? 'seat (loose)'
                : `buy + seat — ${picked ? Number(picked.price / 10n ** 18n) : 0}`}
            </button>
          )}

          {occupied && (
            <>
              <button
                disabled={busy || !augApproved}
                onClick={() =>
                  send(`swap bay ${bayIndex} → ${picked?.ticker}`, {
                    address: addresses.Ripperdoc,
                    abi: RipperdocAbi,
                    functionName: 'swapAugment',
                    args: [tokenId, bi, BigInt(pick)],
                  })
                }
              >
                swap — {swapNet} $AUG
              </button>
              <button
                disabled={busy}
                onClick={() =>
                  send(`sell back bay ${bayIndex}`, {
                    address: addresses.Ripperdoc,
                    abi: RipperdocAbi,
                    functionName: 'sellBackAugment',
                    args: [tokenId, bi],
                  })
                }
              >
                sell back +{resale}
              </button>
            </>
          )}
        </div>
      </td>
    </tr>
  );
}
