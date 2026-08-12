'use client';

import {useAccount, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {BlackMarketAbi, StockRunnerAbi, RUNAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {useOwnedUnits} from '@/components/Inventory';
import {line} from '../vendors';
import {UnitPreview} from '../UnitPreview';
import {useState} from 'react';

const MAX_UINT = 2n ** 256n - 1n;

/** The Fence's stall. Genesis on the left, the rack on the right, and he has opinions about both. */
export function MarketScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [sellPick, setSellPick] = useState<number | undefined>();
  // Whatever was last single-clicked stands in the centre preview, from either list.
  const [inspect, setInspect] = useState<number | undefined>();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'poolSize'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'inventory'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'buyTotal', args: [false]},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'buyTotal', args: [true]},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'sellNet'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'mintingOpen'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'totalMinted'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'GENESIS_PRICE'},
      {address: addresses.RUN, abi: RUNAbi, functionName: 'allowance', args: [address!, addresses.BlackMarket]},
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.BlackMarket],
      },
    ],
    query: {enabled: !!address},
  });

  const poolSize = Number((data?.[0]?.result as bigint | undefined) ?? 0n);
  const inventory = (data?.[1]?.result as readonly bigint[] | undefined) ?? [];
  const randomQ = data?.[2]?.result as readonly bigint[] | undefined;
  const specificQ = data?.[3]?.result as readonly bigint[] | undefined;
  const sellQ = data?.[4]?.result as readonly bigint[] | undefined;
  const mintOpen = data?.[5]?.result === true;
  const minted = data?.[6]?.result as bigint | undefined;
  const price = (data?.[7]?.result as bigint | undefined) ?? 0n;
  const allowance = (data?.[8]?.result as bigint | undefined) ?? 0n;
  const nftApproved = (data?.[9]?.result as boolean | undefined) ?? false;

  const needsApproval = allowance < price;

  return (
    <>
      <UnitPreview
        tokenId={inspect}
        caption={
          inspect === undefined
            ? 'Click anything on the rack to look it over.'
            : sellPick === inspect
              ? 'Yours — selected to sell'
              : 'On the rack'
        }
      />

    <div className="shop-menu">
      <h3 style={{marginBottom: 10}}>Stock</h3>

      {needsApproval && (
        <button
          className="btn primary"
          style={{width: '100%', marginBottom: 12}}
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
          let him take $RUN
        </button>
      )}

      {/* Genesis */}
      <div className="panel" style={{marginBottom: 12, background: 'rgba(0,0,0,0.4)'}}>
        <div className="between">
          <div>
            <div className="mono" style={{fontSize: 12}}>
              BLANK UNIT
            </div>
            <div className="faint" style={{fontSize: 11}}>
              {minted?.toString() ?? '—'} / 333 activated
            </div>
          </div>
          <button
            className="btn primary"
            disabled={busy || !mintOpen || needsApproval}
            onClick={() => {
              onSay(line('market', 'mintOpen'));
              send('activate a unit', {
                address: addresses.BlackMarket,
                abi: BlackMarketAbi,
                functionName: 'activateGenesis',
              });
            }}
            onMouseEnter={() => onSay(line('market', mintOpen ? 'mintOpen' : 'mintClosed'))}
          >
            {mintOpen ? `${fmt(price, 18, 0)} $RUN` : 'not yet'}
          </button>
        </div>
      </div>

      {/* The rack */}
      <h3 style={{marginBottom: 8}}>The rack</h3>
      {poolSize === 0 ? (
        <div
          className="faint"
          style={{fontSize: 12}}
          onMouseEnter={() => onSay(line('market', 'poolEmpty'))}
        >
          Empty. Nobody is selling.
        </div>
      ) : (
        <>
          <button
            className="btn"
            style={{width: '100%', marginBottom: 8}}
            disabled={busy || needsApproval}
            onMouseEnter={() => onSay(line('market', 'random'))}
            onClick={() =>
              send('take pot luck', {
                address: addresses.BlackMarket,
                abi: BlackMarketAbi,
                functionName: 'buyRandom',
                args: [randomQ ? (randomQ[2] * 105n) / 100n : MAX_UINT],
              })
            }
          >
            pot luck · {fmt(randomQ?.[2], 18, 0)} $RUN
          </button>

          <div className="inv-grid" onMouseEnter={() => onSay(line('market', 'specific'))}>
            {inventory.map((id) => {
              const n = Number(id);
              return (
                <button
                  key={id.toString()}
                  className={`item-chip ${inspect === n ? 't3' : ''}`}
                  onClick={() => setInspect(n)}
                >
                  <div>
                    <div style={{fontSize: 12, fontWeight: 600}}>#{String(id).padStart(4, '0')}</div>
                    <div className="faint" style={{fontSize: 10}}>
                      {fmt(specificQ?.[2], 18, 0)}
                    </div>
                  </div>
                </button>
              );
            })}
          </div>

          {inspect !== undefined && inventory.some((i) => Number(i) === inspect) && (
            <button
              className="btn primary"
              style={{width: '100%', marginTop: 8}}
              disabled={busy || needsApproval}
              onClick={() =>
                send(`buy #${inspect}`, {
                  address: addresses.BlackMarket,
                  abi: BlackMarketAbi,
                  functionName: 'buySpecific',
                  args: [BigInt(inspect), specificQ ? (specificQ[2] * 105n) / 100n : MAX_UINT],
                })
              }
            >
              take #{String(inspect).padStart(4, '0')} · {fmt(specificQ?.[2], 18, 0)} $RUN
            </button>
          )}
        </>
      )}

      {/* Selling */}
      <h3 style={{margin: '14px 0 8px'}}>Sell him one</h3>
      {owned.length === 0 ? (
        <div className="faint" style={{fontSize: 12}}>
          You hold nothing he wants.
        </div>
      ) : (
        <div
          className="grid"
          style={{gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 6}}
          onMouseEnter={() => onSay(line('market', 'sell'))}
        >
          {owned.map((id) => (
            <button
              key={id}
              className={`unit-card ${sellPick === id ? 'selected' : ''}`}
              onClick={() => {
                setSellPick(id);
                setInspect(id);
              }}
            >
              <div className="uid">#{String(id).padStart(4, '0')}</div>
              <div className="umodel">yours</div>
            </button>
          ))}
        </div>
      )}

      <div className="row" style={{marginTop: 8}}>
        {!nftApproved ? (
          <button
            className="btn sm"
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
            approve
          </button>
        ) : (
          <button
            className="btn primary"
            style={{flex: 1}}
            disabled={busy || sellPick === undefined}
            onClick={() =>
              send(`sell #${sellPick}`, {
                address: addresses.BlackMarket,
                abi: BlackMarketAbi,
                functionName: 'sell',
                args: [BigInt(sellPick!), sellQ ? (sellQ[2] * 95n) / 100n : 0n],
              })
            }
          >
            {sellPick === undefined
              ? 'pick one above'
              : `sell #${String(sellPick).padStart(4, '0')} · ${fmt(sellQ?.[2], 18, 0)} $RUN`}
          </button>
        )}
      </div>
    </div>
    </>
  );
}
