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
import {line} from '../vendors';
import {CentrePanel, BigStat, Line} from '../CentrePanel';

const MAX_UINT = 2n ** 256n - 1n;

/**
 * The Terminal — the one stall with nobody behind the counter.
 *
 * Presented as a machine rather than a shop: the centre panel is a wall readout, the dialogue is
 * the kiosk printing at you in caps, and there is no vendor cutout. That absence is a design point
 * in the spec, not an art asset that hasn't arrived — anyone can push revenue through here without
 * anyone's cooperation, and the interface should say so by having no one to cooperate with.
 */
export function TerminalScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const [tab, setTab] = useState<'aug' | 'lp'>('aug');

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
  const pool = tab === 'aug' ? augPool : lpPool;
  const totalStaked = (augPool?.[1] ?? 0n) + (lpPool?.[1] ?? 0n);
  const pending = (augPool?.[2] ?? 0n) + (lpPool?.[2] ?? 0n);

  return (
    <>
      <CentrePanel title="TERMINAL // REVENUE" sub="NO OPERATOR PRESENT">
        <BigStat
          value={fmt(pending, 18, 4)}
          unit=" $RUN"
          label="YOURS, ACCRUED SO FAR"
          tone={pending > 0n ? 'lime' : undefined}
        />

        <div className="centre-rule" />

        <Line k="STAKED, ALL POOLS" v={fmt(totalStaked, 18, 0)} />
        <Line k="LEFT IN $AUG STREAM" v={fmt(augRemaining, 18, 0)} />
        <Line k="LEFT IN LP STREAM" v={fmt(lpRemaining, 18, 0)} />
        {/* Purely informational. It sweeps itself into the streams the next time anyone stakes,
            claims or withdraws — there is no button here because there is nothing to press. */}
        <Line k="INBOUND FROM FEES" v={fmt(waiting, 18, 0)} tone={waiting > 0n ? 'sodium' : undefined} />

        <div className="centre-rule" />

        {/* The kiosk is the one place that reads your wallet back to you — everywhere else you are
            looking at a machine's holdings rather than your own. */}
        <div className="centre-sub mono" style={{marginBottom: 6}}>
          YOUR WALLET
        </div>
        <Wallet />

        <p className="faint centre-note">
          Fees reach the streams on their own — the kiosk sweeps whatever is waiting every time
          anyone stakes, claims or withdraws. Revenue then pays out across a full cycle rather than
          in a lump, so the stream sets the rate, never your access to your own funds.
        </p>
      </CentrePanel>

      <div className="shop-menu">
        <h3 style={{marginBottom: 10}}>Kiosk</h3>

        <div className="tabs">
          <button
            className={`tab ${tab === 'aug' ? 'active' : ''}`}
            onClick={() => setTab('aug')}
            onMouseEnter={() => onSay(line('terminal', 'enter'))}
          >
            Stake $AUG · 20%
          </button>
          <button
            className={`tab ${tab === 'lp' ? 'active' : ''}`}
            onClick={() => setTab('lp')}
            onMouseEnter={() => onSay(line('terminal', 'enter'))}
          >
            Liquidity · 20%
          </button>
        </div>

        <StakePanel
          key={tab}
          isLp={tab === 'lp'}
          pool={pool}
          remaining={tab === 'aug' ? augRemaining : lpRemaining}
          token={tab === 'aug' ? addresses.AUG : addresses.MockLpToken}
          abi={tab === 'aug' ? AUGAbi : MockLpTokenAbi}
          symbol={tab === 'aug' ? '$AUG' : 'LP'}
          onSay={onSay}
        />
      </div>
    </>
  );
}

/** Gas plus the three tokens the protocol actually moves. USDG carries the real Global Dollar's
 *  6 decimals, so it is read and formatted separately rather than assumed to be 18. */
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
      <Line k="ETH" v={eth ? Number(eth.formatted).toFixed(6) : '—'} />
      <Line k="$RUN" v={fmt(data?.[0]?.result as bigint | undefined, 18, 2)} />
      <Line k="$AUG" v={fmt(data?.[1]?.result as bigint | undefined, 18, 2)} />
      <Line k="USDG" v={fmt(data?.[2]?.result as bigint | undefined, usdgDecimals, 2)} />
    </>
  );
}

function StakePanel({
  isLp,
  pool,
  remaining,
  token,
  abi,
  symbol,
  onSay,
}: {
  isLp: boolean;
  pool?: readonly bigint[];
  remaining?: bigint;
  token: `0x${string}`;
  abi: any;
  symbol: string;
  onSay: (s: string) => void;
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
  const wallet = (data?.[1]?.result as bigint | undefined) ?? 0n;

  const staked = pool?.[0] ?? 0n;
  const total = pool?.[1] ?? 0n;
  const pending = pool?.[2] ?? 0n;
  const rate = pool?.[3] ?? 0n;
  const queued = pool?.[5] ?? 0n;

  const parsed = (() => {
    try {
      return amount ? BigInt(Math.floor(Number(amount) * 1e18)) : 0n;
    } catch {
      return 0n;
    }
  })();
  const needsApproval = parsed > 0n && allowance < parsed;
  const daily = total > 0n ? (rate * 86400n * staked) / total : 0n;
  const sharePct = total > 0n ? Number((staked * 10_000n) / total) / 100 : 0;

  return (
    <>
      <div className="gauge">
        <div className="gauge-bar">
          <div className="gauge-fill" style={{width: `${Math.min(100, sharePct)}%`}} />
        </div>
        <div className="gauge-legend mono">
          <span>your share {sharePct.toFixed(2)}%</span>
          <span>{fmt(total, 18, 0)} {symbol} pooled</span>
        </div>
      </div>

      <div className="kv-grid">
        <div className="kv">
          <span className="kv-k">your stake</span>
          <span className="kv-v">{fmt(staked)} {symbol}</span>
        </div>
        <div className="kv">
          <span className="kv-k">in wallet</span>
          <span className="kv-v">{fmt(wallet)} {symbol}</span>
        </div>
        <div className="kv">
          <span className="kv-k">claimable</span>
          <span className="kv-v lime">{fmt(pending, 18, 4)} $RUN</span>
        </div>
        <div className="kv">
          <span className="kv-k">your rate</span>
          <span className="kv-v">~{fmt(daily, 18, 2)} /day</span>
        </div>
      </div>

      {queued > 0n && (
        <div className="notice" style={{marginTop: 10, padding: '9px 11px'}}>
          <span style={{fontSize: 11.5}}>
            {fmt(queued, 18, 0)} $RUN is held aside because nothing is staked here yet — streaming
            into an empty pool would destroy it. The first stake starts it.
          </span>
        </div>
      )}

      <div className="row" style={{marginTop: 12}}>
        <input
          placeholder="amount"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          style={{flex: 1}}
        />
        <button className="btn sm ghost" onClick={() => setAmount(String(Number(wallet) / 1e18))}>
          max
        </button>
      </div>

      <div className="row" style={{marginTop: 8}}>
        {needsApproval ? (
          <button
            className="btn primary"
            style={{flex: 1}}
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
            approve {symbol}
          </button>
        ) : (
          <button
            className="btn primary"
            style={{flex: 1}}
            disabled={busy || parsed === 0n}
            onMouseEnter={() => onSay(line('terminal', 'staked'))}
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
          disabled={busy || pending === 0n}
          onMouseEnter={() => onSay(line('terminal', 'claim'))}
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
          disabled={busy || staked === 0n}
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

      <div className="row" style={{marginTop: 8}}>
        <span className="faint" style={{fontSize: 11}}>
          Left in this stream: {fmt(remaining, 18, 0)} $RUN
        </span>
      </div>

      {isLp && (
        <div className="notice" style={{marginTop: 12, padding: '9px 11px'}}>
          <span className="dim" style={{fontSize: 11}}>
            StonkBrokers launches into a Uniswap V3 pool, and a V3 position is an NFT rather than a
            fungible token. This pool takes an ERC-20 today; V3 position staking is still to be built.
          </span>
        </div>
      )}
    </>
  );
}
