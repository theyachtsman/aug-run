'use client';

import {useState} from 'react';
import {useAccount, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {ChopShopAbi, MockUSDGAbi, AugmentsAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';

const MAX_UINT = 2n ** 256n - 1n;
const DP = 6; // USDG has 6 decimals, matching the real Global Dollar
const ROLL_STATE = ['—', 'Committed', 'Won', 'Lost', 'Refunded'];

const usdg = (v: string) => {
  const n = Number(v || '0');
  return BigInt(Math.floor(n * 10 ** DP));
};

export function ChopShopClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();
  const [augId, setAugId] = useState('1');
  const [declared, setDeclared] = useState('1000');
  const [backing, setBacking] = useState('1000');

  const dv = usdg(declared);
  const bk = usdg(backing);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextListingId'},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextRollId'},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'allowance', args: [address!, addresses.ChopShop]},
      {
        address: addresses.Augments,
        abi: AugmentsAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.ChopShop],
      },
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'winProbabilityBps', args: [dv, bk]},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'entryCost', args: [dv, bk]},
    ],
    query: {enabled: !!address},
  });

  const nListings = Number((data?.[0]?.result as bigint | undefined) ?? 1n) - 1;
  const nRolls = Number((data?.[1]?.result as bigint | undefined) ?? 1n) - 1;
  const balance = data?.[2]?.result as bigint | undefined;
  const allowance = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const augApproved = (data?.[4]?.result as boolean | undefined) ?? false;
  const p = data?.[5]?.result as bigint | undefined;
  const entry = data?.[6]?.result as bigint | undefined;

  if (!isConnected) return <NotConnected />;

  const floor = (dv * 2500n) / 10_000n;
  const belowFloor = bk < floor;
  const needsUsdg = allowance < 10_000n * 10n ** BigInt(DP);

  return (
    <>
      <div className="panel" style={{marginBottom: 16}}>
        <div className="between">
          <Stat k="Your USDG" v={fmt(balance, DP, 2)} accent />
          <div className="row">
            <button
              className="btn sm"
              disabled={busy}
              onClick={() =>
                send('mint test USDG', {
                  address: addresses.USDG,
                  abi: MockUSDGAbi,
                  functionName: 'mint',
                  args: [address!, 100_000n * 10n ** BigInt(DP)],
                })
              }
            >
              mint 100,000 test USDG
            </button>
            {needsUsdg && (
              <button
                className="btn primary"
                disabled={busy}
                onClick={() =>
                  send('approve USDG', {
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
          </div>
        </div>
        <Rule>
          USDG is not deployed on this chain, so this is a stand-in with the real token&apos;s 6
          decimals. Swapped for the real one at mainnet.
        </Rule>
      </div>

      {/* --------------------------------------------------------- LIST */}
      <section className="panel" style={{marginBottom: 16}}>
        <h2 style={{marginBottom: 10}}>Put something on the table</h2>

        <div className="row">
          <input value={augId} onChange={(e) => setAugId(e.target.value)} style={{width: 70}} />
          <span className="faint" style={{fontSize: 11}}>
            augment id
          </span>
          <input value={declared} onChange={(e) => setDeclared(e.target.value)} style={{width: 100}} />
          <span className="faint" style={{fontSize: 11}}>
            declared value
          </span>
          <input value={backing} onChange={(e) => setBacking(e.target.value)} style={{width: 100}} />
          <span className="faint" style={{fontSize: 11}}>
            your backing
          </span>

          {!augApproved ? (
            <button
              className="btn primary"
              disabled={busy}
              onClick={() =>
                send('approve Augments', {
                  address: addresses.Augments,
                  abi: AugmentsAbi,
                  functionName: 'setApprovalForAll',
                  args: [addresses.ChopShop, true],
                })
              }
            >
              approve Augments
            </button>
          ) : (
            <button
              className="btn primary"
              disabled={busy || belowFloor}
              onClick={() =>
                send('list on the table', {
                  address: addresses.ChopShop,
                  abi: ChopShopAbi,
                  functionName: 'list',
                  args: [1, addresses.Augments, BigInt(augId || '1'), dv, bk],
                })
              }
            >
              list it
            </button>
          )}
        </div>

        <div className="row" style={{marginTop: 12}}>
          <span className="tag on">
            odds {p !== undefined ? `${Number(p) / 100}%` : '—'}
          </span>
          <span className="tag">entry {fmt(entry, DP, 2)} USDG</span>
          <span className="tag">floor {fmt(floor, DP, 2)} USDG</span>
        </div>

        {belowFloor && (
          <div className="notice hot" style={{marginTop: 10, padding: '10px 12px'}}>
            <span style={{fontSize: 12}}>
              Backing must be at least 25% of declared value — a heavily-built item cannot be listed
              at trivial backing.
            </span>
          </div>
        )}

        <Rule>
          <strong>The less you back it with, the better everyone&apos;s odds.</strong> p = V / (V + B).
          Entry costs the expected value of the roll plus 30%; 10% of that is protocol revenue.
          Declared value is self-policing — understate it and your item is easy to win; overstate it
          and nobody plays.
        </Rule>
      </section>

      <TheTable nListings={nListings} nRolls={nRolls} />
    </>
  );
}

function TheTable({nListings, nRolls}: {nListings: number; nRolls: number}) {
  const {address} = useAccount();
  const {send, busy} = useTx();

  const listingIds = Array.from({length: Math.max(0, nListings)}, (_, i) => BigInt(i + 1));
  const rollIds = Array.from({length: Math.max(0, nRolls)}, (_, i) => BigInt(i + 1));

  const {data: ld} = useReadContracts({
    contracts: listingIds.flatMap((id) => [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'listings' as const, args: [id]},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'listingEntryCost' as const, args: [id]},
    ]),
    query: {enabled: listingIds.length > 0},
  });

  const {data: rd} = useReadContracts({
    contracts: rollIds.map((id) => ({
      address: addresses.ChopShop,
      abi: ChopShopAbi,
      functionName: 'rolls' as const,
      args: [id],
    })),
    query: {enabled: rollIds.length > 0},
  });

  return (
    <>
      <section className="panel" style={{marginBottom: 14}}>
        <div className="between" style={{marginBottom: 10}}>
          <h2>The table</h2>
          <span className="faint mono" style={{fontSize: 11}}>
            rotates daily
          </span>
        </div>

        {listingIds.length === 0 ? (
          <div className="dim">Nothing on the table.</div>
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
                const l = ld?.[i * 2]?.result as any;
                const cost = ld?.[i * 2 + 1]?.result as bigint | undefined;
                if (!l) return null;
                const dv = l[4] as bigint;
                const bk = l[5] as bigint;
                const open = l[7] as boolean;
                const settled = l[8] as boolean;
                const pct = dv > 0n ? Number((dv * 10_000n) / (dv + bk)) / 100 : 0;
                return (
                  <tr key={id.toString()}>
                    <td>{id.toString()}</td>
                    <td>{fmt(dv, DP, 0)}</td>
                    <td>{fmt(bk, DP, 0)}</td>
                    <td style={{color: 'var(--chrome)'}}>{pct}%</td>
                    <td>{fmt(cost, DP, 0)}</td>
                    <td>
                      <span className={`tag ${open ? 'on' : 'off'}`}>
                        {settled ? 'settled' : open ? 'open' : 'rolling'}
                      </span>
                    </td>
                    <td style={{textAlign: 'right'}}>
                      <button
                        className="btn sm"
                        disabled={busy || !open || settled}
                        onClick={() =>
                          send(`roll for listing #${id}`, {
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
      </section>

      <section className="panel">
        <h2 style={{marginBottom: 10}}>Your rolls</h2>
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
                const r = rd?.[i]?.result as any;
                if (!r) return null;
                if ((r[1] as string)?.toLowerCase() !== address?.toLowerCase()) return null;
                const state = Number(r[5]);
                return (
                  <tr key={id.toString()}>
                    <td>{id.toString()}</td>
                    <td>#{(r[0] as bigint).toString()}</td>
                    <td>{fmt(r[2] as bigint, DP, 0)}</td>
                    <td>
                      <span className={`tag ${state === 2 ? 'on' : state === 3 ? 'off' : ''}`}>
                        {ROLL_STATE[state]}
                      </span>
                    </td>
                    <td style={{textAlign: 'right'}}>
                      <div className="row" style={{justifyContent: 'flex-end', gap: 5}}>
                        {state === 1 && (
                          <>
                            <button
                              className="btn sm"
                              disabled={busy}
                              onClick={() =>
                                send(`settle roll #${id}`, {
                                  address: addresses.ChopShop,
                                  abi: ChopShopAbi,
                                  functionName: 'resolve',
                                  args: [id],
                                })
                              }
                            >
                              settle
                            </button>
                            <button
                              className="btn sm ghost"
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
                              refund
                            </button>
                          </>
                        )}
                        {state === 2 &&
                          (
                            [
                              ['take the item', 0],
                              ['cash out 85%', 1],
                              ['convert 90%', 2],
                            ] as const
                          ).map(([label, mode]) => (
                            <button
                              key={mode}
                              className="btn sm"
                              disabled={busy}
                              onClick={() =>
                                send(`claim roll #${id}`, {
                                  address: addresses.ChopShop,
                                  abi: ChopShopAbi,
                                  functionName: 'claim',
                                  args: [id, mode],
                                })
                              }
                            >
                              {label}
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
        <Rule>
          A roll is two steps: <strong>roll</strong> commits, then <strong>settle</strong> reads a
          block that did not exist when you committed — so nobody, including the house, can know the
          outcome in advance. Settling is permissionless. A roll that outruns its ~25 second window
          refunds in full.
        </Rule>
      </section>
    </>
  );
}
