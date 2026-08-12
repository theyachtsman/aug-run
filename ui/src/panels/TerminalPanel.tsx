import {useState} from 'react';
import {useAccount, useReadContracts} from 'wagmi';
import {addresses} from '../addresses';
import {
  TerminalAbi,
  MockLpTokenAbi,
  AUGAbi,
  RUNAbi,
  RevenueSplitterAbi,
} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt} from '../lib/format';

const MAX_UINT = 2n ** 256n - 1n;

export function TerminalPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'poolInfo', args: [false, address!]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'poolInfo', args: [true, address!]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'remainingRewards', args: [false]},
      {address: addresses.Terminal, abi: TerminalAbi, functionName: 'remainingRewards', args: [true]},
      {
        address: addresses.AUG,
        abi: AUGAbi,
        functionName: 'allowance',
        args: [address!, addresses.Terminal],
      },
      {
        address: addresses.MockLpToken,
        abi: MockLpTokenAbi,
        functionName: 'allowance',
        args: [address!, addresses.Terminal],
      },
      {address: addresses.AUG, abi: AUGAbi, functionName: 'balanceOf', args: [address!]},
      {
        address: addresses.MockLpToken,
        abi: MockLpTokenAbi,
        functionName: 'balanceOf',
        args: [address!],
      },
      {
        address: addresses.RevenueSplitter,
        abi: RevenueSplitterAbi,
        functionName: 'balances',
        args: [addresses.RUN],
      },
      {address: addresses.RUN, abi: RUNAbi, functionName: 'balanceOf', args: [address!]},
    ],
    query: {enabled: !!address},
  });

  const augPool = data?.[0]?.result as readonly bigint[] | undefined;
  const lpPool = data?.[1]?.result as readonly bigint[] | undefined;
  const augRemaining = data?.[2]?.result as bigint | undefined;
  const lpRemaining = data?.[3]?.result as bigint | undefined;
  const augAllowance = (data?.[4]?.result as bigint | undefined) ?? 0n;
  const lpAllowance = (data?.[5]?.result as bigint | undefined) ?? 0n;
  const augBalance = data?.[6]?.result as bigint | undefined;
  const lpBalance = data?.[7]?.result as bigint | undefined;
  const splits = data?.[8]?.result as readonly bigint[] | undefined;
  const runBalance = data?.[9]?.result as bigint | undefined;

  const pendingInSplitter = (splits?.[1] ?? 0n) + (splits?.[2] ?? 0n);

  return (
    <div className="panel">
      <h2>The Terminal — stake $AUG, earn protocol revenue</h2>

      <div className="spread">
        <span className="dim">unclaimed in splitter (stakers + LPs)</span>
        <span className="mono">{fmt(pendingInSplitter, 18, 0)} $RUN</span>
      </div>
      <div className="row" style={{marginTop: 8}}>
        <button
          disabled={busy || pendingInSplitter === 0n}
          onClick={() =>
            send('pull rewards into the Terminal', {
              address: addresses.Terminal,
              abi: TerminalAbi,
              functionName: 'pullRewards',
            })
          }
        >
          pull rewards → start streams
        </button>
        <span className="note">
          permissionless — the Terminal is unstaffed, so anyone can push revenue to stakers
        </span>
      </div>

      <StakePool
        title="$AUG staking — 20% of every fee"
        isLp={false}
        pool={augPool}
        remaining={augRemaining}
        allowance={augAllowance}
        walletBalance={augBalance}
        tokenAddress={addresses.AUG}
        tokenAbi={AUGAbi}
        symbol="$AUG"
      />

      <StakePool
        title="Liquidity staking — 20% of every fee"
        isLp
        pool={lpPool}
        remaining={lpRemaining}
        allowance={lpAllowance}
        walletBalance={lpBalance}
        tokenAddress={addresses.MockLpToken}
        tokenAbi={MockLpTokenAbi}
        symbol="LP"
        mintable
      />

      <div className="note">
        Rewards stream over one 7-day cycle rather than landing in a lump, so staking right before a
        pull and leaving straight after earns nothing. Stake, unstake and claim are always available
        — the stream sets the accrual rate, never access to your funds.
      </div>
      <div className="note">
        Your $RUN balance: <span className="mono">{fmt(runBalance, 18, 2)}</span>
      </div>
    </div>
  );
}

function StakePool({
  title,
  isLp,
  pool,
  remaining,
  allowance,
  walletBalance,
  tokenAddress,
  tokenAbi,
  symbol,
  mintable,
}: {
  title: string;
  isLp: boolean;
  pool?: readonly bigint[];
  remaining?: bigint;
  allowance: bigint;
  walletBalance?: bigint;
  tokenAddress: `0x${string}`;
  tokenAbi: any;
  symbol: string;
  mintable?: boolean;
}) {
  const {send, busy} = useTx();
  const [amount, setAmount] = useState('');

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

  // Rough daily rate for this wallet's share, purely informational.
  const dailyShare =
    rate && staked && total && total > 0n ? (rate * 86400n * staked) / total : 0n;

  return (
    <div className="unit" style={{marginTop: 12}}>
      <h3 style={{marginTop: 0}}>{title}</h3>

      <div className="grid2" style={{gap: 8}}>
        <div>
          <div className="spread">
            <span className="dim">your stake</span>
            <span className="mono">
              {fmt(staked)} {symbol}
            </span>
          </div>
          <div className="spread">
            <span className="dim">pool total</span>
            <span className="mono">
              {fmt(total)} {symbol}
            </span>
          </div>
          <div className="spread">
            <span className="dim">wallet</span>
            <span className="mono">
              {fmt(walletBalance)} {symbol}
            </span>
          </div>
        </div>
        <div>
          <div className="spread">
            <span className="dim">claimable now</span>
            <span className="mono" style={{color: 'var(--ok)'}}>
              {fmt(pending, 18, 4)} $RUN
            </span>
          </div>
          <div className="spread">
            <span className="dim">your rate</span>
            <span className="mono">~{fmt(dailyShare, 18, 2)} $RUN/day</span>
          </div>
          <div className="spread">
            <span className="dim">left in stream</span>
            <span className="mono">{fmt(remaining, 18, 0)} $RUN</span>
          </div>
        </div>
      </div>

      {(queued ?? 0n) > 0n && (
        <div className="note" style={{color: 'var(--warn)'}}>
          {fmt(queued, 18, 0)} $RUN queued — nothing is staked in this pool yet, so it's held rather
          than streamed into an empty pool. The first stake starts it.
        </div>
      )}

      <div className="row" style={{marginTop: 10}}>
        <input
          placeholder="amount"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          style={{width: 130}}
        />
        {needsApproval ? (
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send(`approve ${symbol}`, {
                address: tokenAddress,
                abi: tokenAbi,
                functionName: 'approve',
                args: [addresses.Terminal, MAX_UINT],
              })
            }
          >
            approve {symbol}
          </button>
        ) : (
          <button
            className="primary"
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
          exit (all + claim)
        </button>
      </div>

      {mintable && <MintMockLp />}
    </div>
  );
}

/// Testnet-only: no DEX exists on this chain, so there is no real $AUG LP token to stake.
function MintMockLp() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  return (
    <div className="note" style={{marginTop: 6}}>
      <button
        disabled={busy || !address}
        onClick={() =>
          send('mint mock LP tokens', {
            address: addresses.MockLpToken,
            abi: MockLpTokenAbi,
            functionName: 'mint',
            args: [address!, 1000n * 10n ** 18n],
          })
        }
      >
        mint 1,000 mock LP
      </button>{' '}
      Robinhood Chain has no DEX yet, so this stands in for a real $AUG pair token. On mainnet the
      Terminal points at the actual Uniswap-V2-style LP token instead.
    </div>
  );
}
