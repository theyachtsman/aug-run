import {useAccount, useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {StockRunnerAbi, RUNAbi, BlackMarketAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt} from '../lib/format';

export function MintPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'totalMinted'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'MAX_SUPPLY'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'GENESIS_PRICE'},
      {
        address: addresses.RUN,
        abi: RUNAbi,
        functionName: 'allowance',
        args: [address!, addresses.BlackMarket],
      },
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'modelRemaining'},
    ],
    query: {enabled: !!address},
  });

  const minted = data?.[0]?.result as bigint | undefined;
  const max = data?.[1]?.result as bigint | undefined;
  const price = (data?.[2]?.result as bigint | undefined) ?? 0n;
  const allowance = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const balance = (data?.[4]?.result as bigint | undefined) ?? 0n;
  const remaining = data?.[5]?.result as readonly number[] | undefined;

  const needsApproval = allowance < price;
  const canAfford = balance >= price;
  const soldOut = minted !== undefined && max !== undefined && minted >= max;

  return (
    <div className="panel">
      <h2>Genesis mint</h2>
      <div className="spread">
        <span className="dim">activated</span>
        <span className="mono">
          {minted?.toString() ?? '—'} / {max?.toString() ?? '333'}
        </span>
      </div>
      <div className="spread">
        <span className="dim">price</span>
        <span className="mono">{fmt(price, 18, 0)} $RUN</span>
      </div>

      <div className="row" style={{marginTop: 10}}>
        <button
          disabled={busy || !needsApproval}
          onClick={() =>
            send('approve $RUN', {
              address: addresses.RUN,
              abi: RUNAbi,
              functionName: 'approve',
              args: [addresses.BlackMarket, price],
            })
          }
        >
          {needsApproval ? '1. approve 1,000,000 $RUN' : '1. approved ✓'}
        </button>
        <button
          className="primary"
          disabled={busy || needsApproval || !canAfford || soldOut}
          onClick={() =>
            send('activate Stock//Runner', {
              address: addresses.BlackMarket,
              abi: BlackMarketAbi,
              functionName: 'activateGenesis',
            })
          }
        >
          2. activate
        </button>
      </div>
      <div className="note">
        Every unit activates through the Black Market, and the 1,000,000 $RUN stays there as pool
        liquidity — that's what lets the pool buy units back later.
      </div>

      {!canAfford && (
        <div className="note" style={{color: 'var(--warn)'}}>
          Not enough $RUN — use the faucet (5,000,000 per claim covers five mints).
        </div>
      )}
      {soldOut && (
        <div className="note" style={{color: 'var(--warn)'}}>
          All 333 activated. There is no mechanism to create more.
        </div>
      )}

      <h3>Model lines remaining</h3>
      <div className="row mono" style={{fontSize: 11}}>
        {remaining?.map((n, i) => (
          <span key={i} className="tag">
            {i}: {n}
          </span>
        ))}
      </div>
      <div className="note">
        Model is assigned by an exact-count bucket draw and is cosmetic only — no model is scarcer
        and none carries any mechanical advantage. You cannot pick one.
      </div>
    </div>
  );
}
