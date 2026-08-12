import {useState} from 'react';
import {useAccount, useReadContracts} from 'wagmi';
import {formatEther, parseUnits} from 'viem';
import {addresses, EXPLORER} from '../addresses';
import {
  BlackMarketAbi,
  RevenueSplitterAbi,
  StockRunnerAbi,
  RUNAbi,
  TestnetRunPriceOracleAbi,
} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt, shortAddr} from '../lib/format';
import {useOwnedUnits} from './UnitsPanel';

const MAX_UINT = 2n ** 256n - 1n;

function tierLabel(bps?: bigint): string {
  if (bps === undefined) return '—';
  if (bps === 2500n) return '25% — below the 0.1 ETH floor';
  if (bps === 1500n) return '15% — between 0.1 and 1 ETH';
  return '10% — above 1 ETH';
}

export function BlackMarketPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: ownedIds} = useOwnedUnits();
  const [sellPick, setSellPick] = useState<number | undefined>(undefined);
  const [oraclePrice, setOraclePrice] = useState('1000000000000');

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
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'lifetimeFees'},
      {
        address: addresses.RevenueSplitter,
        abi: RevenueSplitterAbi,
        functionName: 'balances',
        args: [addresses.RUN],
      },
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
      {address: addresses.PriceOracle, abi: TestnetRunPriceOracleAbi, functionName: 'ethPerRun'},
    ],
    query: {enabled: !!address},
  });

  const quoteBuy = data?.[0]?.result as bigint | undefined;
  const quoteSell = data?.[1]?.result as bigint | undefined;
  const poolSize = data?.[2]?.result as bigint | undefined;
  const poolLiquidity = data?.[3]?.result as bigint | undefined;
  const inventory = (data?.[4]?.result as readonly bigint[] | undefined) ?? [];
  const randomQuote = data?.[5]?.result as readonly bigint[] | undefined;
  const specificQuote = data?.[6]?.result as readonly bigint[] | undefined;
  const sellQuote = data?.[7]?.result as readonly bigint[] | undefined;
  const sellFeeBps = data?.[8]?.result as bigint | undefined;
  const unitValueWei = data?.[9]?.result as bigint | undefined;
  const lifetimeFees = data?.[10]?.result as bigint | undefined;
  const splits = data?.[11]?.result as readonly bigint[] | undefined;
  const runAllowance = (data?.[12]?.result as bigint | undefined) ?? 0n;
  const nftApproved = (data?.[13]?.result as boolean | undefined) ?? false;
  const ethPerRun = data?.[14]?.result as bigint | undefined;

  const needsRunApproval = runAllowance < (specificQuote?.[2] ?? 0n);
  const canSellPool = (poolLiquidity ?? 0n) >= (quoteSell ?? 0n);

  return (
    <div className="panel">
      <h2>The Black Market — the Fence</h2>

      <div className="grid2" style={{gap: 8}}>
        <div>
          <div className="spread">
            <span className="dim">pool quote (buy)</span>
            <span className="mono">{fmt(quoteBuy, 18, 0)} $RUN</span>
          </div>
          <div className="spread">
            <span className="dim">pool quote (sell)</span>
            <span className="mono">{fmt(quoteSell, 18, 0)} $RUN</span>
          </div>
          <div className="spread">
            <span className="dim">units in pool</span>
            <span className="mono">{poolSize?.toString() ?? '—'}</span>
          </div>
          <div className="spread">
            <span className="dim">pool liquidity</span>
            <span className="mono">{fmt(poolLiquidity, 18, 0)} $RUN</span>
          </div>
        </div>
        <div>
          <div className="spread">
            <span className="dim">unit value</span>
            <span className="mono">
              {unitValueWei !== undefined ? `${Number(formatEther(unitValueWei)).toFixed(4)} ETH` : '—'}
            </span>
          </div>
          <div className="spread">
            <span className="dim">sell fee tier</span>
            <span className="mono">{tierLabel(sellFeeBps)}</span>
          </div>
          <div className="spread">
            <span className="dim">lifetime fees</span>
            <span className="mono">{fmt(lifetimeFees, 18, 0)} $RUN</span>
          </div>
        </div>
      </div>

      {needsRunApproval && (
        <div className="row" style={{marginTop: 10}}>
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve $RUN for the Black Market', {
                address: addresses.RUN,
                abi: RUNAbi,
                functionName: 'approve',
                args: [addresses.BlackMarket, MAX_UINT],
              })
            }
          >
            approve $RUN for the Black Market
          </button>
        </div>
      )}

      {/* ---------------------------------------------------------- BUY */}
      <h3>Buy from the pool</h3>
      {(poolSize ?? 0n) === 0n ? (
        <div className="dim">
          Pool is empty — nobody has sold a unit in yet. Activate one below, or sell one to seed it.
        </div>
      ) : (
        <>
          <div className="row">
            <button
              disabled={busy || needsRunApproval}
              onClick={() =>
                send('buy random unit', {
                  address: addresses.BlackMarket,
                  abi: BlackMarketAbi,
                  functionName: 'buyRandom',
                  args: [randomQuote ? (randomQuote[2] * 105n) / 100n : MAX_UINT],
                })
              }
            >
              buy random — {fmt(randomQuote?.[2], 18, 0)} $RUN (10% fee)
            </button>
          </div>
          <table style={{marginTop: 8}}>
            <thead>
              <tr>
                <th>unit</th>
                <th>price + 15% fee</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {inventory.map((id) => (
                <tr key={id.toString()}>
                  <td className="mono">#{id.toString()}</td>
                  <td className="mono">{fmt(specificQuote?.[2], 18, 0)} $RUN</td>
                  <td>
                    <button
                      disabled={busy || needsRunApproval}
                      onClick={() =>
                        send(`buy unit #${id}`, {
                          address: addresses.BlackMarket,
                          abi: BlackMarketAbi,
                          functionName: 'buySpecific',
                          args: [id, specificQuote ? (specificQuote[2] * 105n) / 100n : MAX_UINT],
                        })
                      }
                    >
                      buy specific
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
      <div className="note">
        Taking pot luck costs 10%; naming the unit you want costs 15%. Each purchase steps the pool
        price up, each sale steps it down.
      </div>

      {/* --------------------------------------------------------- SELL */}
      <h3>Sell to the pool</h3>
      <div className="row">
        <select
          value={sellPick ?? ''}
          onChange={(e) => setSellPick(e.target.value ? Number(e.target.value) : undefined)}
        >
          <option value="">select a unit…</option>
          {ownedIds.map((id) => (
            <option key={id} value={id}>
              #{id}
            </option>
          ))}
        </select>

        {!nftApproved ? (
          <button
            disabled={busy}
            onClick={() =>
              send('approve units for the Black Market', {
                address: addresses.StockRunner,
                abi: StockRunnerAbi,
                functionName: 'setApprovalForAll',
                args: [addresses.BlackMarket, true],
              })
            }
          >
            approve units for sale
          </button>
        ) : (
          <button
            disabled={busy || sellPick === undefined || !canSellPool}
            onClick={() =>
              send(`sell unit #${sellPick}`, {
                address: addresses.BlackMarket,
                abi: BlackMarketAbi,
                functionName: 'sell',
                args: [BigInt(sellPick!), sellQuote ? (sellQuote[2] * 95n) / 100n : 0n],
              })
            }
          >
            sell — receive {fmt(sellQuote?.[2], 18, 0)} $RUN
          </button>
        )}
      </div>
      {!canSellPool && (
        <div className="note" style={{color: 'var(--warn)'}}>
          Pool doesn't hold enough $RUN to buy a unit right now. Genesis activations capitalise it.
        </div>
      )}
      <div className="note">
        You receive the pool's sell quote less the tiered fee ({tierLabel(sellFeeBps)}). The pool
        never buys at its own ask — that spread is what stops a round trip draining it.
      </div>

      {/* ------------------------------------------------------- SPLITS */}
      <h3>Where the fees go — 60 / 20 / 20</h3>
      <table>
        <thead>
          <tr>
            <th>bucket</th>
            <th>accrued $RUN</th>
            <th>status</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>Drop (60%)</td>
            <td className="mono">{fmt(splits?.[0], 18, 0)}</td>
            <td className="dim">phase 8</td>
          </tr>
          <tr>
            <td>$AUG stakers (20%)</td>
            <td className="mono">{fmt(splits?.[1], 18, 0)}</td>
            <td className="dim">phase 5</td>
          </tr>
          <tr>
            <td>$AUG LPs (20%)</td>
            <td className="mono">{fmt(splits?.[2], 18, 0)}</td>
            <td className="dim">phase 5</td>
          </tr>
        </tbody>
      </table>
      <div className="note">
        Recipients aren't wired yet — the Terminal (phase 5) and the Drop (phase 8) claim these once
        they exist. Nothing is lost in the meantime. A 5% ERC-2981 royalty on external sales lands in
        the same split via{' '}
        <a href={`${EXPLORER}/address/${addresses.RevenueSplitter}`} target="_blank" rel="noreferrer">
          {shortAddr(addresses.RevenueSplitter)}
        </a>
        .
      </div>

      {/* ---------------------------------------------------- DEV PANEL */}
      <div className="panel devpanel" style={{marginTop: 12, marginBottom: 0}}>
        <h2 style={{color: 'var(--warn)'}}>Dev panel — $RUN price oracle</h2>
        <div className="spread">
          <span className="dim">ethPerRun (wei per $RUN)</span>
          <span className="mono">{ethPerRun?.toString() ?? '—'}</span>
        </div>
        <div className="row" style={{marginTop: 8}}>
          <input
            value={oraclePrice}
            onChange={(e) => setOraclePrice(e.target.value)}
            style={{width: 180}}
          />
          <button
            disabled={busy}
            onClick={() =>
              send('set $RUN price', {
                address: addresses.PriceOracle,
                abi: TestnetRunPriceOracleAbi,
                functionName: 'setEthPerRun',
                args: [BigInt(oraclePrice || '0')],
              })
            }
          >
            set
          </button>
          {[
            ['5e10 → 25% tier', '50000000000'],
            ['1e12 → 15% tier', '1000000000000'],
            ['2e12 → 10% tier', '2000000000000'],
          ].map(([label, value]) => (
            <button key={value} disabled={busy} onClick={() => setOraclePrice(value)}>
              {label}
            </button>
          ))}
        </div>
        <div className="note">
          Robinhood Chain testnet has no DEX and no price feed, so this stands in for a real $RUN/ETH
          TWAP. Push it across the 0.1 ETH and 1 ETH thresholds to exercise all three sell fee tiers.
          Mainnet points the Black Market at a real oracle through the same interface.
        </div>
      </div>
    </div>
  );
}
