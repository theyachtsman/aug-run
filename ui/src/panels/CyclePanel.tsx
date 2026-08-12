import {useEffect, useState} from 'react';
import {useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {StockRunnerAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {countdown} from '../lib/format';

export function CyclePanel() {
  const {send, busy} = useTx();
  const [, tick] = useState(0);

  // Local 1s tick so the countdown moves without hammering the RPC.
  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'currentCycle'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'nextCycleBoundary'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'cycleOffset'},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'TESTNET'},
    ],
  });

  const cycle = data?.[0]?.result as bigint | undefined;
  const boundary = Number((data?.[1]?.result as bigint | undefined) ?? 0n);
  const offset = data?.[2]?.result as bigint | undefined;
  const isTestnet = data?.[3]?.result as boolean | undefined;

  const now = Math.floor(Date.now() / 1000);
  const remaining = boundary > now ? boundary - now : 0;
  const boundaryDate = boundary ? new Date(boundary * 1000) : undefined;

  return (
    <div className="panel">
      <h2>Cycle clock</h2>
      <div className="spread">
        <span className="dim">current cycle</span>
        <span className="mono" style={{fontSize: 20}}>
          {cycle?.toString() ?? '—'}
        </span>
      </div>
      <div className="spread">
        <span className="dim">next boundary in</span>
        <span className="mono">{countdown(remaining)}</span>
      </div>
      <div className="spread">
        <span className="dim">boundary (UTC)</span>
        <span className="mono">
          {boundaryDate
            ? boundaryDate.toISOString().replace('T', ' ').replace('.000Z', ' UTC')
            : '—'}
        </span>
      </div>
      <div className="note">
        Weekly epochs anchored to Monday 00:00 UTC. The same clock governs rebinding, seasoning and
        tenure accrual, so there is only ever one deadline to track.
      </div>

      {isTestnet && (
        <div className="panel devpanel" style={{marginTop: 12, marginBottom: 0}}>
          <h2 style={{color: 'var(--warn)'}}>Dev panel — testnet only</h2>
          <div className="spread">
            <span className="dim">cycle offset</span>
            <span className="mono">+{offset?.toString() ?? '0'}</span>
          </div>
          <div className="row" style={{marginTop: 8}}>
            {[1, 2, 8, 9].map((n) => (
              <button
                key={n}
                disabled={busy}
                onClick={() =>
                  send(`advance ${n} cycle${n > 1 ? 's' : ''}`, {
                    address: addresses.StockRunner,
                    abi: StockRunnerAbi,
                    functionName: 'advanceCycles',
                    args: [BigInt(n)],
                  })
                }
              >
                +{n}
              </button>
            ))}
          </div>
          <div className="note">
            Fast-forwards the effective cycle so tenure and seasoning are testable in minutes rather
            than over eight real weeks. +9 takes a freshly seated Augment to the 1.5x tenure
            ceiling. Gated behind the immutable TESTNET flag — reverts on a mainnet deployment.
          </div>
        </div>
      )}
    </div>
  );
}
