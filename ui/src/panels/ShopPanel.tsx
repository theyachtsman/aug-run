import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {AugmentsAbi, ExpansionModulesAbi, RipperdocAbi, AUGAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt} from '../lib/format';

export type CatalogEntry = {id: number; ticker: string; tier: number; price: bigint; loose: bigint};

export function useCatalog(): CatalogEntry[] {
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
    price: d.tier === 1 ? 100n * 10n ** 18n : d.tier === 2 ? 250n * 10n ** 18n : 500n * 10n ** 18n,
    loose: ((balances as readonly bigint[] | undefined)?.[i] ?? 0n),
  }));
}

export function ShopPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const catalog = useCatalog();

  const {data} = useReadContracts({
    contracts: [
      {
        address: addresses.AUG,
        abi: AUGAbi,
        functionName: 'allowance',
        args: [address!, addresses.Ripperdoc],
      },
      {
        address: addresses.ExpansionModules,
        abi: ExpansionModulesAbi,
        functionName: 'balanceOf',
        args: [address!],
      },
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'totalBurned'},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'totalToReserve'},
    ],
    query: {enabled: !!address},
  });

  const allowance = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const looseModules = (data?.[1]?.result as bigint | undefined) ?? 0n;
  const burned = data?.[2]?.result as bigint | undefined;
  const toReserve = data?.[3]?.result as bigint | undefined;

  const MAX = 2n ** 256n - 1n;
  const lowAllowance = allowance < 10_000n * 10n ** 18n;

  return (
    <div className="panel">
      <h2>The Ripperdoc</h2>

      {lowAllowance && (
        <div className="row" style={{marginBottom: 10}}>
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve $AUG', {
                address: addresses.AUG,
                abi: AUGAbi,
                functionName: 'approve',
                args: [addresses.Ripperdoc, MAX],
              })
            }
          >
            approve $AUG for the Ripperdoc
          </button>
          <span className="note">required once before buying anything</span>
        </div>
      )}

      <table>
        <thead>
          <tr>
            <th>id</th>
            <th>ticker</th>
            <th>tier</th>
            <th>weight</th>
            <th>price</th>
            <th>loose</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {catalog.map((a) => (
            <tr key={a.id}>
              <td className="dim mono">{a.id}</td>
              <td>
                <strong>{a.ticker}</strong>
              </td>
              <td>
                <span className={`tag t${a.tier}`}>T{a.tier}</span>
              </td>
              <td className="mono dim">
                {a.tier === 1 ? '1.0x' : a.tier === 2 ? '1.25x' : '1.5x'}
              </td>
              <td className="mono">{fmt(a.price, 18, 0)}</td>
              <td className="mono">{a.loose > 0n ? a.loose.toString() : '—'}</td>
              <td>
                <button
                  disabled={busy}
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
              </td>
            </tr>
          ))}
          <tr>
            <td className="dim mono">—</td>
            <td>
              <strong>Expansion Module</strong>
            </td>
            <td>
              <span className="tag">MOD</span>
            </td>
            <td className="mono dim">+1 bay</td>
            <td className="mono">500</td>
            <td className="mono">{looseModules > 0n ? looseModules.toString() : '—'}</td>
            <td>
              <button
                disabled={busy}
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
            </td>
          </tr>
        </tbody>
      </table>

      <div className="note">
        Half of every $AUG payment burns permanently; half funds the protocol reserve. Lifetime:{' '}
        <span className="mono">{fmt(burned, 18, 0)}</span> burned /{' '}
        <span className="mono">{fmt(toReserve, 18, 0)}</span> to reserve.
      </div>
      <div className="note">
        Loose Augments are ordinary transferable ERC-1155 balances. Seating one burns it and binds it
        permanently to that unit.
      </div>
    </div>
  );
}
