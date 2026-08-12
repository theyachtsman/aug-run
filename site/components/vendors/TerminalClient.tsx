'use client';

import {useState} from 'react';
import {useAccount, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {TerminalAbi, AUGAbi, MockLpTokenAbi, RevenueSplitterAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';

const MAX_UINT = 2n ** 256n - 1n;

export function TerminalClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();

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
        <div className="between">
          <div>
            <Stat k="Revenue waiting in the splitter" v={`${fmt(waiting, 18, 0)} $RUN`} accent />
            <Rule>
              Nobody&apos;s cooperation is required for revenue to reach stakers — anyone can push it
              through. The kiosk is unstaffed by design.
            </Rule>
          </div>
          <button
            className="btn"
            disabled={busy || waiting === 0n}
            onClick={() =>
              send('push revenue to stakers', {
                address: addresses.Terminal,
                abi: TerminalAbi,
                functionName: 'pullRewards',
              })
            }
          >
            release revenue
          </button>
        </div>
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
