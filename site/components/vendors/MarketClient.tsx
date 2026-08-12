'use client';

import {useAccount, useReadContracts} from 'wagmi';
import {formatEther} from 'viem';
import {addresses} from '@/lib/addresses';
import {BlackMarketAbi, StockRunnerAbi, RUNAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';
import {useOwnedUnits} from '@/components/Inventory';
import {useState} from 'react';

const MAX_UINT = 2n ** 256n - 1n;

function tierName(bps?: bigint) {
  if (bps === undefined) return '—';
  if (bps === 2500n) return '25% · under 0.1 ETH';
  if (bps === 1500n) return '15% · 0.1 – 1 ETH';
  return '10% · above 1 ETH';
}

export function MarketClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [sellPick, setSellPick] = useState<number | undefined>();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'quoteBuy'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'quoteSell'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'poolSize'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'poolLiquidity'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'inventory'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'buyTotal', args: [false]},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'buyTotal', args: [true]},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'sellNet'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'sellFeeBps'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'unitValueInWei'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'mintingOpen'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'totalMinted'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'GENESIS_PRICE'},
      {
        address: addresses.RUN,
        abi: RUNAbi,
        functionName: 'allowance',
        args: [address!, addresses.BlackMarket],
      },
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.BlackMarket],
      },
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'modelRemaining'},
    ],
    query: {enabled: !!address},
  });

  const quoteBuy = data?.[0]?.result as bigint | undefined;
  const poolSize = Number((data?.[2]?.result as bigint | undefined) ?? 0n);
  const poolLiquidity = data?.[3]?.result as bigint | undefined;
  const inventory = (data?.[4]?.result as readonly bigint[] | undefined) ?? [];
  const randomQ = data?.[5]?.result as readonly bigint[] | undefined;
  const specificQ = data?.[6]?.result as readonly bigint[] | undefined;
  const sellQ = data?.[7]?.result as readonly bigint[] | undefined;
  const sellFeeBps = data?.[8]?.result as bigint | undefined;
  const unitWei = data?.[9]?.result as bigint | undefined;
  const mintOpen = data?.[10]?.result === true;
  const minted = data?.[11]?.result as bigint | undefined;
  const genesisPrice = (data?.[12]?.result as bigint | undefined) ?? 0n;
  const runAllowance = (data?.[13]?.result as bigint | undefined) ?? 0n;
  const nftApproved = (data?.[14]?.result as boolean | undefined) ?? false;
  const remaining = data?.[15]?.result as readonly number[] | undefined;

  if (!isConnected) return <NotConnected />;

  const needsRunApproval = runAllowance < (specificQ?.[2] ?? genesisPrice);
  const poolCanBuy = (poolLiquidity ?? 0n) >= (sellQ?.[0] ?? 0n) && (sellQ?.[0] ?? 0n) > 0n;

  return (
    <>
      {needsRunApproval && (
        <div className="notice" style={{marginBottom: 16}}>
          <div className="between">
            <span className="dim">
              The Fence needs permission to take $RUN before you can trade.
            </span>
            <button
              className="btn primary"
              disabled={busy}
              onClick={() =>
                send('approve $RUN', {
                  address: addresses.RUN,
                  abi: RUNAbi,
                  functionName: 'approve',
                  args: [addresses.BlackMarket, MAX_UINT],
                })
              }
            >
              approve $RUN
            </button>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------- GENESIS */}
      <section className="panel" style={{marginBottom: 16}}>
        <div className="between" style={{marginBottom: 10}}>
          <h2>Genesis</h2>
          <span className={`tag ${mintOpen ? 'on' : 'warn'}`}>
            {mintOpen ? 'open' : 'closed'}
          </span>
        </div>

        <div className="grid g2">
          <div>
            <Stat k="Activated" v={`${minted?.toString() ?? '—'} / 333`} />
            <Stat k="Price" v={`${fmt(genesisPrice, 18, 0)} $RUN`} accent />
            <Stat k="Bays at activation" v="1 of 3" />
            <button
              className="btn primary"
              style={{marginTop: 12, width: '100%'}}
              disabled={busy || !mintOpen || needsRunApproval}
              onClick={() =>
                send('activate a Stock//Runner', {
                  address: addresses.BlackMarket,
                  abi: BlackMarketAbi,
                  functionName: 'activateGenesis',
                })
              }
            >
              {mintOpen ? 'activate a blank unit' : 'genesis has not opened'}
            </button>
          </div>

          <div>
            <h3 style={{marginTop: 0}}>Model lines remaining</h3>
            <div className="row" style={{gap: 5}}>
              {remaining?.map((n, i) => (
                <span key={i} className="tag mono" style={{fontSize: 10}}>
                  {i}:{n}
                </span>
              ))}
            </div>
            <Rule>
              Model is assigned by an exact-count draw bound to your own address, so it cannot be
              rerolled and cannot be chosen. It is cosmetic — no model is scarcer and none carries a
              mechanical advantage. The 1,000,000 $RUN stays here as pool liquidity, which is what
              lets the pool buy units back later.
            </Rule>
          </div>
        </div>
      </section>

      {/* ---------------------------------------------------------- POOL */}
      <section className="grid g2" style={{marginBottom: 16}}>
        <div className="panel">
          <h2>Buy off the rack</h2>
          <Stat k="Pool quote" v={`${fmt(quoteBuy, 18, 0)} $RUN`} accent />
          <Stat k="Units in pool" v={String(poolSize)} />
          <Stat k="Pool liquidity" v={`${fmt(poolLiquidity, 18, 0)} $RUN`} />

          {poolSize === 0 ? (
            <div className="dim" style={{fontSize: 12.5, marginTop: 12}}>
              Nothing on the rack. The pool only holds units operators have sold in.
            </div>
          ) : (
            <>
              <button
                className="btn primary"
                style={{marginTop: 12, width: '100%'}}
                disabled={busy || needsRunApproval}
                onClick={() =>
                  send('buy a random unit', {
                    address: addresses.BlackMarket,
                    abi: BlackMarketAbi,
                    functionName: 'buyRandom',
                    args: [randomQ ? (randomQ[2] * 105n) / 100n : MAX_UINT],
                  })
                }
              >
                take pot luck — {fmt(randomQ?.[2], 18, 0)} $RUN (10%)
              </button>

              <table style={{marginTop: 14}}>
                <thead>
                  <tr>
                    <th>unit</th>
                    <th>with 15% fee</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {inventory.map((id) => (
                    <tr key={id.toString()}>
                      <td>#{String(id).padStart(4, '0')}</td>
                      <td>{fmt(specificQ?.[2], 18, 0)}</td>
                      <td style={{textAlign: 'right'}}>
                        <button
                          className="btn sm"
                          disabled={busy || needsRunApproval}
                          onClick={() =>
                            send(`buy unit #${id}`, {
                              address: addresses.BlackMarket,
                              abi: BlackMarketAbi,
                              functionName: 'buySpecific',
                              args: [id, specificQ ? (specificQ[2] * 105n) / 100n : MAX_UINT],
                            })
                          }
                        >
                          pick this one
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}
          <Rule>
            Taking pot luck costs 10%; naming the unit you want costs 15%. Each purchase steps the
            pool price up, each sale steps it down.
          </Rule>
        </div>

        <div className="panel">
          <h2>Sell to the pool</h2>
          <Stat k="Pool pays" v={`${fmt(sellQ?.[2], 18, 0)} $RUN`} accent sub="after the tiered fee" />
          <Stat k="Fee tier" v={tierName(sellFeeBps)} />
          <Stat
            k="Unit value"
            v={unitWei !== undefined ? `${Number(formatEther(unitWei)).toFixed(4)} ETH` : '—'}
          />

          <div className="row" style={{marginTop: 12}}>
            <select
              value={sellPick ?? ''}
              onChange={(e) => setSellPick(e.target.value ? Number(e.target.value) : undefined)}
              style={{flex: 1}}
            >
              <option value="">select one of your units…</option>
              {owned.map((id) => (
                <option key={id} value={id}>
                  #{String(id).padStart(4, '0')}
                </option>
              ))}
            </select>

            {!nftApproved ? (
              <button
                className="btn"
                disabled={busy}
                onClick={() =>
                  send('approve units', {
                    address: addresses.StockRunner,
                    abi: StockRunnerAbi,
                    functionName: 'setApprovalForAll',
                    args: [addresses.BlackMarket, true],
                  })
                }
              >
                approve units
              </button>
            ) : (
              <button
                className="btn"
                disabled={busy || sellPick === undefined || !poolCanBuy}
                onClick={() =>
                  send(`sell unit #${sellPick}`, {
                    address: addresses.BlackMarket,
                    abi: BlackMarketAbi,
                    functionName: 'sell',
                    args: [BigInt(sellPick!), sellQ ? (sellQ[2] * 95n) / 100n : 0n],
                  })
                }
              >
                sell
              </button>
            )}
          </div>

          {!poolCanBuy && (
            <div className="dim" style={{fontSize: 12, marginTop: 8, color: 'var(--sodium)'}}>
              The pool cannot cover a purchase right now. Genesis activations capitalise it.
            </div>
          )}

          <Rule>
            The pool quotes one price for every unit it holds, so it cannot pay a premium for a built
            Runner — and is not meant to. This is the floor and instant liquidity. A tenured unit is
            worth more than the floor, and that trade belongs on an external venue, where the 5%
            royalty still funds the protocol.
          </Rule>
        </div>
      </section>
    </>
  );
}
