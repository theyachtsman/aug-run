import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {
  ChopShopAbi,
  MockUSDGAbi,
  AugmentsAbi,
  CommitRevealRandomnessAbi,
} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt} from '../lib/format';
import {useCatalog} from './ShopPanel';

const MAX_UINT = 2n ** 256n - 1n;
const USDG_DP = 6;

/** USDG has 6 decimals, matching the real Global Dollar. */
function toUsdg(v: string): bigint {
  const n = Number(v || '0');
  return BigInt(Math.floor(n * 10 ** USDG_DP));
}

const ROLL_STATE = ['—', 'Committed', 'Won', 'Lost', 'Refunded'];

export function ChopShopPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const catalog = useCatalog();

  const [augPick, setAugPick] = useState(1);
  const [declared, setDeclared] = useState('1000');
  const [backing, setBacking] = useState('1000');

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextListingId'},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextRollId'},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'balanceOf', args: [address!]},
      {
        address: addresses.USDG,
        abi: MockUSDGAbi,
        functionName: 'allowance',
        args: [address!, addresses.ChopShop],
      },
      {
        address: addresses.Augments,
        abi: AugmentsAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.ChopShop],
      },
    ],
    query: {enabled: !!address},
  });

  const nextListing = Number((data?.[0]?.result as bigint | undefined) ?? 1n);
  const nextRoll = Number((data?.[1]?.result as bigint | undefined) ?? 1n);
  const usdgBalance = data?.[2]?.result as bigint | undefined;
  const usdgAllowance = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const augmentsApproved = (data?.[4]?.result as boolean | undefined) ?? false;

  const dv = toUsdg(declared);
  const bk = toUsdg(backing);

  const {data: quote} = useReadContracts({
    contracts: [
      {
        address: addresses.ChopShop,
        abi: ChopShopAbi,
        functionName: 'winProbabilityBps',
        args: [dv, bk],
      },
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'entryCost', args: [dv, bk]},
    ],
    query: {enabled: dv > 0n},
  });

  const pBps = quote?.[0]?.result as bigint | undefined;
  const entry = quote?.[1]?.result as bigint | undefined;
  const floor = (dv * 2500n) / 10_000n;
  const belowFloor = bk < floor;

  return (
    <div className="panel">
      <h2>The Chop Shop — the Scrapper's table</h2>

      <div className="spread">
        <span className="dim">your USDG</span>
        <span className="mono">{fmt(usdgBalance, USDG_DP, 2)}</span>
      </div>
      <div className="row" style={{marginTop: 8}}>
        <button
          disabled={busy}
          onClick={() =>
            send('mint test USDG', {
              address: addresses.USDG,
              abi: MockUSDGAbi,
              functionName: 'mint',
              args: [address!, 100_000n * 10n ** BigInt(USDG_DP)],
            })
          }
        >
          mint 100,000 test USDG
        </button>
        {usdgAllowance < 10_000n * 10n ** BigInt(USDG_DP) && (
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve USDG for the Chop Shop', {
                address: addresses.USDG,
                abi: MockUSDGAbi,
                functionName: 'approve',
                args: [addresses.ChopShop, MAX_UINT],
              })
            }
          >
            approve USDG
          </button>
        )}
        {!augmentsApproved && (
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve Augments for the Chop Shop', {
                address: addresses.Augments,
                abi: AugmentsAbi,
                functionName: 'setApprovalForAll',
                args: [addresses.ChopShop, true],
              })
            }
          >
            approve Augments
          </button>
        )}
      </div>
      <div className="note">
        USDG isn't deployed on this chain, so this is a mock with the real token's 6 decimals.
      </div>

      {/* ------------------------------------------------------ LIST */}
      <h3>Put an Augment on the table</h3>
      <div className="row">
        <select value={augPick} onChange={(e) => setAugPick(Number(e.target.value))}>
          {catalog.map((c) => (
            <option key={c.id} value={c.id}>
              {c.ticker} T{c.tier}
              {c.loose > 0n ? ` · ${c.loose} loose` : ' · none loose'}
            </option>
          ))}
        </select>
        <input value={declared} onChange={(e) => setDeclared(e.target.value)} style={{width: 90}} />
        <span className="dim">declared value</span>
        <input value={backing} onChange={(e) => setBacking(e.target.value)} style={{width: 90}} />
        <span className="dim">backing</span>
        <button
          className="primary"
          disabled={busy || belowFloor || !augmentsApproved}
          onClick={() =>
            send('list on the table', {
              address: addresses.ChopShop,
              abi: ChopShopAbi,
              functionName: 'list',
              args: [1, addresses.Augments, BigInt(augPick), dv, bk],
            })
          }
        >
          list
        </button>
      </div>

      <div className="row" style={{marginTop: 8}}>
        <span className="tag">
          win chance {pBps !== undefined ? `${Number(pBps) / 100}%` : '—'}
        </span>
        <span className="tag">entry {fmt(entry, USDG_DP, 2)} USDG</span>
        <span className="tag">floor {fmt(floor, USDG_DP, 2)} USDG</span>
      </div>
      {belowFloor && (
        <div className="note" style={{color: 'var(--err)'}}>
          Backing is below the 25% floor — a built item can't be listed at trivial backing.
        </div>
      )}
      <div className="note">
        <strong>The less you back it with, the better everyone's odds.</strong> p = V / (V + B).
        Entry costs the expected value of the roll plus 30%; 10% of that is protocol revenue. The
        table rotates daily.
      </div>

      <Table nextListing={nextListing} nextRoll={nextRoll} />
    </div>
  );
}

function Table({nextListing, nextRoll}: {nextListing: number; nextRoll: number}) {
  const {address} = useAccount();
  const {send, busy} = useTx();

  const listingIds = Array.from({length: Math.max(0, nextListing - 1)}, (_, i) => BigInt(i + 1));
  const rollIds = Array.from({length: Math.max(0, nextRoll - 1)}, (_, i) => BigInt(i + 1));

  const {data: listingData} = useReadContracts({
    contracts: listingIds.flatMap((id) => [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'listings' as const, args: [id]},
      {
        address: addresses.ChopShop,
        abi: ChopShopAbi,
        functionName: 'listingEntryCost' as const,
        args: [id],
      },
    ]),
    query: {enabled: listingIds.length > 0},
  });

  const {data: rollData} = useReadContracts({
    contracts: rollIds.flatMap((id) => [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'rolls' as const, args: [id]},
    ]),
    query: {enabled: rollIds.length > 0},
  });

  return (
    <>
      <h3>The table</h3>
      {listingIds.length === 0 ? (
        <div className="dim">Nothing on the table yet.</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>value</th>
              <th>backing</th>
              <th>odds</th>
              <th>entry</th>
              <th>state</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {listingIds.map((id, i) => {
              const l = listingData?.[i * 2]?.result as any;
              const cost = listingData?.[i * 2 + 1]?.result as bigint | undefined;
              if (!l) return null;
              const declaredValue = l[4] as bigint;
              const backing = l[5] as bigint;
              const open = l[7] as boolean;
              const settled = l[8] as boolean;
              const p =
                declaredValue > 0n
                  ? Number((declaredValue * 10_000n) / (declaredValue + backing)) / 100
                  : 0;
              return (
                <tr key={id.toString()}>
                  <td className="mono">{id.toString()}</td>
                  <td className="mono">{fmt(declaredValue, USDG_DP, 0)}</td>
                  <td className="mono">{fmt(backing, USDG_DP, 0)}</td>
                  <td className="mono">{p}%</td>
                  <td className="mono">{fmt(cost, USDG_DP, 0)}</td>
                  <td>
                    <span className={`tag ${open ? 'eligible' : 'locked'}`}>
                      {settled ? 'settled' : open ? 'open' : 'rolling'}
                    </span>
                  </td>
                  <td>
                    <button
                      disabled={busy || !open || settled}
                      onClick={() =>
                        send(`roll listing #${id}`, {
                          address: addresses.ChopShop,
                          abi: ChopShopAbi,
                          functionName: 'roll',
                          args: [id],
                        })
                      }
                    >
                      roll
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <h3>Your rolls</h3>
      {rollIds.length === 0 ? (
        <div className="dim">No rolls yet.</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>listing</th>
              <th>entry</th>
              <th>state</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rollIds.map((id, i) => {
              const r = rollData?.[i]?.result as any;
              if (!r) return null;
              const mine = (r[1] as string)?.toLowerCase() === address?.toLowerCase();
              if (!mine) return null;
              const state = Number(r[5]);
              return (
                <tr key={id.toString()}>
                  <td className="mono">{id.toString()}</td>
                  <td className="mono">#{(r[0] as bigint).toString()}</td>
                  <td className="mono">{fmt(r[2] as bigint, USDG_DP, 0)}</td>
                  <td>
                    <span className={`tag ${state === 2 ? 'eligible' : state === 3 ? 'locked' : ''}`}>
                      {ROLL_STATE[state]}
                    </span>
                  </td>
                  <td>
                    <div className="row">
                      {state === 1 && (
                        <>
                          <button
                            disabled={busy}
                            onClick={() =>
                              send(`resolve roll #${id}`, {
                                address: addresses.ChopShop,
                                abi: ChopShopAbi,
                                functionName: 'resolve',
                                args: [id],
                              })
                            }
                          >
                            resolve
                          </button>
                          <button
                            disabled={busy}
                            onClick={() =>
                              send(`refund roll #${id}`, {
                                address: addresses.ChopShop,
                                abi: ChopShopAbi,
                                functionName: 'refundExpiredRoll',
                                args: [id],
                              })
                            }
                          >
                            refund if expired
                          </button>
                        </>
                      )}
                      {state === 2 &&
                        [
                          ['take item', 0],
                          ['cash out 85%', 1],
                          ['convert 90%', 2],
                        ].map(([label, mode]) => (
                          <button
                            key={mode as number}
                            disabled={busy}
                            onClick={() =>
                              send(`claim roll #${id}`, {
                                address: addresses.ChopShop,
                                abi: ChopShopAbi,
                                functionName: 'claim',
                                args: [id, mode as number],
                              })
                            }
                          >
                            {label as string}
                          </button>
                        ))}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      <div className="note">
        Rolls are two-step: <strong>roll</strong> commits, then <strong>resolve</strong> settles once
        the target block lands (a couple of blocks later). Resolution is permissionless so a keeper
        can do it. Chainlink VRF isn't available on this chain, so entropy comes from a future block
        hash — a request that outruns its ~25 second window expires and refunds in full.
      </div>
    </>
  );
}
