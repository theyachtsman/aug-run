import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {DropAbi, RevenueSplitterAbi, AugmentsAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt, fmtWeight, countdown} from '../lib/format';
import {useOwnedUnits} from './UnitsPanel';

const PHASE = ['—', 'Accumulating', 'Claimable', 'Closed'];

export function DropPanel() {
  const {send, busy} = useTx();
  const {ids: ownedIds} = useOwnedUnits();

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
      {address: addresses.Drop, abi: DropAbi, functionName: 'dustFloor'},
      {address: addresses.Drop, abi: DropAbi, functionName: 'skippedPool', args: [id]},
      {address: addresses.Augments, abi: AugmentsAbi, functionName: 'augmentCount'},
    ],
    query: {enabled: id > 0n},
  });

  const round = data?.[0]?.result as readonly bigint[] | undefined;
  const progress = data?.[1]?.result as readonly bigint[] | undefined;
  const splits = data?.[2]?.result as readonly bigint[] | undefined;
  const buyback = data?.[3]?.result as bigint | undefined;
  const floor = data?.[4]?.result as bigint | undefined;
  const skipped = data?.[5]?.result as bigint | undefined;

  const phase = round ? Number(round[6]) : 0;
  const pool = round?.[1];
  const totalWeight = round?.[2];
  const deadline = Number(round?.[5] ?? 0n);
  const pending = splits?.[0] ?? 0n;
  const now = Math.floor(Date.now() / 1000);
  const accDone = progress ? progress[0] > progress[1] : false;

  return (
    <div className="panel">
      <h2>The Drop — revenue becomes real-world assets</h2>

      <div className="grid2" style={{gap: 8}}>
        <div>
          <div className="spread">
            <span className="dim">waiting in the 60% bucket</span>
            <span className="mono">{fmt(pending, 18, 0)} $RUN</span>
          </div>
          <div className="spread">
            <span className="dim">current drop</span>
            <span className="mono">
              #{id.toString()} · {PHASE[phase]}
            </span>
          </div>
          <div className="spread">
            <span className="dim">pool</span>
            <span className="mono">{fmt(pool, 18, 0)} $RUN</span>
          </div>
        </div>
        <div>
          <div className="spread">
            <span className="dim">total eligible weight</span>
            <span className="mono">{fmtWeight(totalWeight)}</span>
          </div>
          <div className="spread">
            <span className="dim">claim window closes in</span>
            <span className="mono">{deadline > now ? countdown(deadline - now) : 'closed'}</span>
          </div>
          <div className="spread">
            <span className="dim">rolled forward / buyback</span>
            <span className="mono">
              {fmt(skipped, 18, 0)} / {fmt(buyback, 18, 0)}
            </span>
          </div>
        </div>
      </div>

      <div className="row" style={{marginTop: 10}}>
        <button
          disabled={busy || pending === 0n}
          onClick={() =>
            send('open a Drop', {address: addresses.Drop, abi: DropAbi, functionName: 'openDrop'})
          }
        >
          1. open drop
        </button>
        <button
          disabled={busy || phase !== 1}
          onClick={() =>
            send('accumulate weights', {
              address: addresses.Drop,
              abi: DropAbi,
              functionName: 'accumulate',
              args: [id, 50n],
            })
          }
        >
          2. accumulate {progress ? `(${progress[0]}/${progress[1]})` : ''}
        </button>
        <button
          disabled={busy || phase !== 1 || !accDone}
          onClick={() =>
            send('finalize the Drop', {
              address: addresses.Drop,
              abi: DropAbi,
              functionName: 'finalize',
              args: [id],
            })
          }
        >
          3. finalize (buy per ticker)
        </button>
      </div>
      <div className="note">
        Every step is permissionless. Weights are read from the Stock//Runner itself, so whoever
        fires a Drop chooses only <em>when</em> it happens, never who earns from it.
      </div>

      <h3>Collect</h3>
      {ownedIds.length === 0 ? (
        <div className="dim">You hold no units.</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>unit</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {ownedIds.map((u) => (
              <tr key={u}>
                <td className="mono">#{u}</td>
                <td>
                  <button
                    disabled={busy || phase !== 2}
                    onClick={() =>
                      send(`claim Drop for #${u}`, {
                        address: addresses.Drop,
                        abi: DropAbi,
                        functionName: 'claim',
                        args: [id, BigInt(u)],
                      })
                    }
                  >
                    claim into unit wallet
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div className="note">
        Delivery is pull-based — assets sit in escrow until you collect them into the unit's ERC-6551
        wallet, and you pay your own gas. Anything unclaimed when the window closes is sold to fund a
        $RUN buyback. Dust floor right now:{' '}
        <span className="mono">{floor !== undefined ? `${Number(floor) / 1e18} ETH` : '—'}</span> —
        below that an amount is held and compounds instead of being delivered.
      </div>
    </div>
  );
}
