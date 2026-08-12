import {useAccount, useBalance, useReadContract, useReadContracts} from 'wagmi';
import {addresses, EXPLORER} from '../addresses';
import {RUNAbi, AUGAbi, RipperdocAbi} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt, shortAddr, countdown} from '../lib/format';

export function WalletPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();

  const {data: eth} = useBalance({address});

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.RUN, abi: RUNAbi, functionName: 'faucetAvailableAt', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'faucetAvailableAt', args: [address!]},
      {address: addresses.RUN, abi: RUNAbi, functionName: 'faucetRemaining'},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'faucetRemaining'},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'augCredit', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'totalSupply'},
    ],
    query: {enabled: !!address},
  });

  const runBal = data?.[0]?.result as bigint | undefined;
  const augBal = data?.[1]?.result as bigint | undefined;
  const runAvailAt = Number((data?.[2]?.result as bigint | undefined) ?? 0n);
  const augAvailAt = Number((data?.[3]?.result as bigint | undefined) ?? 0n);
  const runFaucetLeft = data?.[4]?.result as bigint | undefined;
  const augFaucetLeft = data?.[5]?.result as bigint | undefined;
  const credit = data?.[6]?.result as bigint | undefined;
  const augSupply = data?.[7]?.result as bigint | undefined;

  const now = Math.floor(Date.now() / 1000);
  const runWait = runAvailAt > now ? runAvailAt - now : 0;
  const augWait = augAvailAt > now ? augAvailAt - now : 0;

  return (
    <div className="panel">
      <h2>Wallet</h2>
      <div className="spread">
        <span className="dim">address</span>
        <a href={`${EXPLORER}/address/${address}`} target="_blank" rel="noreferrer">
          {shortAddr(address)}
        </a>
      </div>
      <div className="spread">
        <span className="dim">ETH (gas)</span>
        <span className="mono">{eth ? fmt(eth.value, 18, 5) : '—'}</span>
      </div>

      <h3>$RUN</h3>
      <div className="spread">
        <span className="mono">{fmt(runBal)}</span>
        <button
          disabled={busy || runWait > 0}
          onClick={() =>
            send('$RUN faucet', {address: addresses.RUN, abi: RUNAbi, functionName: 'faucet'})
          }
        >
          {runWait > 0 ? `cooldown ${countdown(runWait)}` : 'faucet +5,000,000'}
        </button>
      </div>
      <div className="note">faucet reserve left: {fmt(runFaucetLeft, 18, 0)}</div>

      <h3>$AUG</h3>
      <div className="spread">
        <span className="mono">{fmt(augBal)}</span>
        <button
          disabled={busy || augWait > 0}
          onClick={() =>
            send('$AUG faucet', {
              address: addresses.AUG,
              abi: AUGAbi,
              functionName: 'faucet',
            })
          }
        >
          {augWait > 0 ? `cooldown ${countdown(augWait)}` : 'faucet +10,000'}
        </button>
      </div>
      <div className="note">faucet reserve left: {fmt(augFaucetLeft, 18, 0)}</div>
      <div className="note">
        $AUG total supply: <span className="mono">{fmt(augSupply, 18, 0)}</span> — falls
        permanently as purchases burn half of every payment.
      </div>

      <h3>Ripperdoc credit</h3>
      <div className="spread">
        <span className="mono">{fmt(credit)} $AUG</span>
        <span className="note">from selling Augments back — spent automatically on next purchase</span>
      </div>
    </div>
  );
}
