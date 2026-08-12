'use client';

import {useState} from 'react';
import {useAccount, useBalance, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {
  TerminalAbi,
  AUGAbi,
  RUNAbi,
  MockUSDGAbi,
  MockLpTokenAbi,
  RevenueSplitterAbi,
} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';

const MAX_UINT = 2n ** 256n - 1n;

export function TerminalClient() {
  const {address, isConnected} = useAccount();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'poolInfo', args: [false, address!]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'poolInfo', args: [true, address!]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'remainingRewards', args: [false]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'remainingRewards', args: [true]},
      {
        address: addresses.RevenueSplitter,
        abi: RevenueSplitterAbi,
        functionName: 'balances',
        args: [addresses.RUN],
      },
    ],
    query: {enabled: !!address},
  });

  const augPool = data?.[0]?.result as readonly bigint[] | undefined;
  const lpPool = data?.[1]?.result as readonly bigint[] | undefined;
  const augRemaining = data?.[2]?.result as bigint | undefined;
  const lpRemaining = data?.[3]?.result as bigint | undefined;
  const splits = data?.[4]?.result as readonly bigint[] | undefined;

  const waiting = (splits?.[1] ?? 0n) + (splits?.[2] ?? 0n);

  if (!isConnected) return <NotConnected />;

  return (
    <>
      <div className="panel" style={{marginBottom: 16}}>
        <h2 style={{marginBottom: 10}}>Your wallet</h2>
        <Wallet />
      </div>

      <div className="panel" style={{marginBottom: 16}}>
        <Stat k="Inbound from fees" v={`${fmt(waiting, 18, 0)} $RUN`} accent />
        <Rule>
          This reaches the streams on its own. The kiosk sweeps whatever is waiting every time anyone
          stakes, claims or withdraws, so nobody has to release anything and nobody&apos;s
          cooperation is required for revenue to reach stakers — which is the point of an unstaffed
          kiosk.
        </Rule>
      </div>

      <div className="grid g2">
        <StakePool
          title="Stake $AUG"
          share="20% of every fee"
          isLp={false}
          pool={augPool}
          remaining={augRemaining}
          token={addresses.AUG}
          abi={AUGAbi}
          symbol="$AUG"
        />
        <StakePool
          title="Provide liquidity"
          share="20% of every fee"
          isLp
          pool={lpPool}
          remaining={lpRemaining}
          token={addresses.MockLpToken}
          abi={MockLpTokenAbi}
          symbol="LP"
          note="StonkBrokers launches into a Uniswap V3 pool, and a V3 position is an NFT rather than a fungible token. This pool takes an ERC-20 today; V3 position staking is still to be built."
        />
      </div>

      <Rule>
        Rewards stream across a full cycle rather than landing in a lump, so staking immediately
        before a release and leaving straight after earns nothing. Staking, unstaking and claiming are
        available at any moment — the stream sets the rate, never your access to your own funds.
      </Rule>
    </>
  );
}

/** Gas plus the three tokens the protocol moves. USDG uses the real Global Dollar's 6 decimals. */
function Wallet() {
  const {address} = useAccount();
  const {data: eth} = useBalance({address, query: {enabled: !!address}});

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'balanceOf', args: [address!]},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'decimals'},
    ],
    query: {enabled: !!address},
  });

  const usdgDecimals = Number((data?.[3]?.result as number | undefined) ?? 6);

  return (
    <>
      <Stat k="ETH" v={eth ? `${Number(eth.formatted).toFixed(6)} ETH` : '—'} sub="gas" />
      <Stat k="$RUN" v={fmt(data?.[0]?.result as bigint | undefined, 18, 2)} accent />
      <Stat k="$AUG" v={fmt(data?.[1]?.result as bigint | undefined, 18, 2)} />
      <Stat k="USDG" v={fmt(data?.[2]?.result as bigint | undefined, usdgDecimals, 2)} />
    </>
  );
}

function StakePool({
  title,
  share,
  isLp,
  pool,
  remaining,
  token,
  abi,
  symbol,
  note,
}: {
  title: string;
  share: string;
  isLp: boolean;
  pool?: readonly bigint[];
  remaining?: bigint;
  token: `0x${string}`;
  abi: any;
  symbol: string;
  note?: string;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const [amount, setAmount] = useState('');

  const {data} = useReadContracts({
    contracts: [
      {address: token, abi, functionName: 'allowance', args: [address!, addresses.Terminal]},
      {address: token, abi, functionName: 'balanceOf', args: [address!]},
    ],
    query: {enabled: !!address},
  });

  const allowance = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const wallet = data?.[1]?.result as bigint | undefined;

  const staked = pool?.[0];
  const total = pool?.[1];
  const pending = pool?.[2];
  const rate = pool?.[3];
  const queued = pool?.[5];

  const parsed = (() => {
    try {
      return amount ? BigInt(Math.floor(Number(amount) * 1e18)) : 0n;
    } catch {
      return 0n;
    }
  })();
  const needsApproval = parsed > 0n && allowance < parsed;
  const daily = rate && staked && total && total > 0n ? (rate * 86400n * staked) / total : 0n;

  return (
    <div className="panel">
      <div className="between" style={{marginBottom: 10}}>
        <h2>{title}</h2>
        <span className="tag">{share}</span>
      </div>

      <Stat k="Your stake" v={`${fmt(staked)} ${symbol}`} />
      <Stat k="Pool total" v={`${fmt(total)} ${symbol}`} />
      <Stat k="Claimable now" v={`${fmt(pending, 18, 4)} $RUN`} accent />
      <Stat k="Your rate" v={`~${fmt(daily, 18, 2)} $RUN / day`} />
      <Stat k="Left in stream" v={`${fmt(remaining, 18, 0)} $RUN`} />
      <Stat k="In wallet" v={`${fmt(wallet)} ${symbol}`} />

      {(queued ?? 0n) > 0n && (
        <div className="notice" style={{marginTop: 10, padding: '10px 12px'}}>
          <span style={{fontSize: 12}}>
            {fmt(queued, 18, 0)} $RUN is held aside because nothing is staked here yet — streaming it
            into an empty pool would destroy it. The first stake starts it.
          </span>
        </div>
      )}

      <div className="row" style={{marginTop: 12}}>
        <input
          placeholder="amount"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          style={{width: 120}}
        />
        {needsApproval ? (
          <button
            className="btn primary"
            disabled={busy}
            onClick={() =>
              send(`approve ${symbol}`, {
                address: token,
                abi,
                functionName: 'approve',
                args: [addresses.Terminal, MAX_UINT],
              })
            }
          >
            approve
          </button>
        ) : (
          <button
            className="btn primary"
            disabled={busy || parsed === 0n}
            onClick={() =>
              send(`stake ${symbol}`, {
                address: addresses.Terminal,
                abi: TerminalAbi,
                functionName: 'stake',
                args: [isLp, parsed],
              })
            }
          >
            stake
          </button>
        )}
        <button
          className="btn sm"
          disabled={busy || parsed === 0n}
          onClick={() =>
            send(`unstake ${symbol}`, {
              address: addresses.Terminal,
              abi: TerminalAbi,
              functionName: 'withdraw',
              args: [isLp, parsed],
            })
          }
        >
          unstake
        </button>
        <button
          className="btn sm"
          disabled={busy || (pending ?? 0n) === 0n}
          onClick={() =>
            send('claim rewards', {
              address: addresses.Terminal,
              abi: TerminalAbi,
              functionName: 'claim',
              args: [isLp],
            })
          }
        >
          claim
        </button>
        <button
          className="btn sm ghost"
          disabled={busy || (staked ?? 0n) === 0n}
          onClick={() =>
            send('exit', {
              address: addresses.Terminal,
              abi: TerminalAbi,
              functionName: 'exit',
              args: [isLp],
            })
          }
        >
          exit
        </button>
      </div>

      {note && (
        <div className="notice" style={{marginTop: 12, padding: '10px 12px'}}>
          <span style={{fontSize: 11.5}} className="dim">
            {note}
          </span>
        </div>
      )}
    </div>
  );
}
