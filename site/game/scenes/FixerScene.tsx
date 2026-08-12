'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {formatEther} from 'viem';
import {addresses} from '@/lib/addresses';
import {
  FixerAbi,
  BlackMarketAbi,
  ProtocolReserveAbi,
  StockRunnerAbi,
  AugmentsAbi,
  RUNAbi,
  AUGAbi,
} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {useOwnedUnits} from '@/components/Inventory';
import {line} from '../vendors';
import {hardware} from '../augmentNames';
import {UnitPreview} from '../UnitPreview';

const MAX_UINT = 2n ** 256n - 1n;
const STATUS = ['—', 'Active', 'Iced', 'Closed'];

/**
 * The Fixer's booth.
 *
 * The centre keeps whatever you are about to pledge, because the decision here is emotional in a
 * way the other shops are not — you are handing over a machine you built, and the interface should
 * make you look at it while you do. LTV is shown as a bar with the ice line drawn on it rather than
 * a percentage, so drift toward 70% is something you watch rather than something you calculate.
 */
export function FixerScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [tab, setTab] = useState<'unit' | 'hardware' | 'paper'>('unit');
  const [pledge, setPledge] = useState<number | undefined>();
  const [term, setTerm] = useState('4');

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Fixer, abi: FixerAbi, functionName: 'quoteRunnerLoan'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'lendableRun'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'totalLent'},
      {address: addresses.ProtocolReserve, abi: ProtocolReserveAbi, functionName: 'balance'},
      {address: addresses.ProtocolReserve, abi: ProtocolReserveAbi, functionName: 'outstanding'},
      {address: addresses.Fixer, abi: FixerAbi, functionName: 'nextRunnerLoanId'},
      {address: addresses.Fixer, abi: FixerAbi, functionName: 'nextAugmentLoanId'},
      {address: addresses.Fixer, abi: FixerAbi, functionName: 'totalInterestBurned'},
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.Fixer],
      },
      {
        address: addresses.Augments,
        abi: AugmentsAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.Fixer],
      },
      {address: addresses.RUN, abi: RUNAbi, functionName: 'allowance', args: [address!, addresses.Fixer]},
      {address: addresses.AUG, abi: AUGAbi, functionName: 'allowance', args: [address!, addresses.Fixer]},
    ],
    query: {enabled: !!address},
  });

  const quote = data?.[0]?.result as readonly bigint[] | undefined;
  const lendable = data?.[1]?.result as bigint | undefined;
  const lent = data?.[2]?.result as bigint | undefined;
  const reserveBal = data?.[3]?.result as bigint | undefined;
  const reserveOut = data?.[4]?.result as bigint | undefined;
  const nRunner = Number((data?.[5]?.result as bigint | undefined) ?? 1n) - 1;
  const nAug = Number((data?.[6]?.result as bigint | undefined) ?? 1n) - 1;
  const burned = data?.[7]?.result as bigint | undefined;
  const unitsApproved = (data?.[8]?.result as boolean | undefined) ?? false;
  const augmentsApproved = (data?.[9]?.result as boolean | undefined) ?? false;
  const runAllowance = (data?.[10]?.result as bigint | undefined) ?? 0n;
  const augAllowance = (data?.[11]?.result as bigint | undefined) ?? 0n;

  const principal = quote?.[0];
  const ethFee = quote?.[1];
  const collateral = quote?.[2];

  return (
    <>
      <UnitPreview
        tokenId={tab === 'unit' ? pledge : undefined}
        caption={
          tab !== 'unit'
            ? 'He only takes units as collateral on this side of the desk.'
            : pledge === undefined
              ? 'Pick a unit to pledge. He will not value it until you do.'
              : `Draws ${fmt(principal, 18, 0)} $RUN · rate ${
                  ethFee !== undefined ? Number(formatEther(ethFee)).toFixed(6) : '—'
                } ETH up front`
        }
      />

      <div className="shop-menu">
        <h3 style={{marginBottom: 10}}>The Booth</h3>

        <div className="tabs">
          <button
            className={`tab ${tab === 'unit' ? 'active' : ''}`}
            onClick={() => setTab('unit')}
            onMouseEnter={() => onSay(line('fixer', 'quote'))}
          >
            Against a unit
          </button>
          <button
            className={`tab ${tab === 'hardware' ? 'active' : ''}`}
            onClick={() => setTab('hardware')}
            onMouseEnter={() => onSay(line('fixer', 'augmentLoan'))}
          >
            Against hardware
          </button>
          <button
            className={`tab ${tab === 'paper' ? 'active' : ''}`}
            onClick={() => setTab('paper')}
            onMouseEnter={() => onSay(line('fixer', 'ltvWarning'))}
          >
            Your paper
          </button>
        </div>

        {tab === 'unit' && (
          <>
            <div className="kv-grid">
              <div className="kv">
                <span className="kv-k">he values a unit at</span>
                <span className="kv-v">{fmt(collateral, 18, 0)} $RUN</span>
              </div>
              <div className="kv">
                <span className="kv-k">you draw (50%)</span>
                <span className="kv-v red">{fmt(principal, 18, 0)} $RUN</span>
              </div>
              <div className="kv">
                <span className="kv-k">rate, up front</span>
                <span className="kv-v">
                  {ethFee !== undefined ? `${Number(formatEther(ethFee)).toFixed(6)} ETH` : '—'}
                </span>
              </div>
              <div className="kv">
                <span className="kv-k">pool can lend</span>
                <span className="kv-v">{fmt(lendable, 18, 0)}</span>
              </div>
            </div>

            {owned.length === 0 ? (
              <div className="faint" style={{fontSize: 12, marginTop: 12}}>
                You own nothing he would take.
              </div>
            ) : (
              <div
                className="grid"
                style={{
                  gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))',
                  gap: 6,
                  marginTop: 12,
                }}
              >
                {owned.map((id) => (
                  <button
                    key={id}
                    className={`unit-card ${pledge === id ? 'selected' : ''}`}
                    onClick={() => setPledge(id)}
                  >
                    <div className="uid">#{String(id).padStart(4, '0')}</div>
                    <div className="umodel">pledge</div>
                  </button>
                ))}
              </div>
            )}

            <div className="row" style={{marginTop: 12}}>
              <input value={term} onChange={(e) => setTerm(e.target.value)} style={{width: 64}} />
              <span className="faint" style={{fontSize: 11}}>
                cycles
              </span>
              {!unitsApproved ? (
                <button
                  className="btn primary"
                  style={{flex: 1}}
                  disabled={busy}
                  onClick={() =>
                    send('approve units', {
                      address: addresses.StockRunner,
                      abi: StockRunnerAbi,
                      functionName: 'setApprovalForAll',
                      args: [addresses.Fixer, true],
                    })
                  }
                >
                  let him hold units
                </button>
              ) : (
                <button
                  className="btn primary"
                  style={{flex: 1}}
                  disabled={busy || pledge === undefined}
                  onClick={() => {
                    onSay(line('fixer', 'ltvWarning'));
                    send(`borrow against #${pledge}`, {
                      address: addresses.Fixer,
                      abi: FixerAbi,
                      functionName: 'borrowAgainstRunner',
                      args: [BigInt(pledge!), BigInt(term || '4')],
                      value: ethFee ?? 0n,
                    });
                  }}
                >
                  {pledge === undefined
                    ? 'pick one above'
                    : `take ${fmt(principal, 18, 0)} $RUN`}
                </button>
              )}
            </div>

            <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
              The rate is paid once, up front, in ETH — nothing accrues on a $RUN loan. LTV still
              drifts on its own, because the pool&apos;s quote moves as units are bought and sold.
              That drift is what the rate prices. Iced at 70%.
            </p>
          </>
        )}

        {tab === 'hardware' && (
          <HardwareLoan
            approved={augmentsApproved}
            reserveBal={reserveBal}
            reserveOut={reserveOut}
            burned={burned}
            onSay={onSay}
          />
        )}

        {tab === 'paper' && (
          <>
            <LoanList
              kind="runner"
              count={nRunner}
              needsAllowance={runAllowance < (principal ?? 0n)}
              approveToken={addresses.RUN}
              approveAbi={RUNAbi}
              onSay={onSay}
            />
            <LoanList
              kind="augment"
              count={nAug}
              needsAllowance={augAllowance < 10_000n * 10n ** 18n}
              approveToken={addresses.AUG}
              approveAbi={AUGAbi}
              onSay={onSay}
            />
          </>
        )}
      </div>
    </>
  );
}

/* -------------------------------------------------------------- HARDWARE */

function HardwareLoan({
  approved,
  reserveBal,
  reserveOut,
  burned,
  onSay,
}: {
  approved: boolean;
  reserveBal?: bigint;
  reserveOut?: bigint;
  burned?: bigint;
  onSay: (s: string) => void;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const [pick, setPick] = useState<number | undefined>();

  const {data: count} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'augmentCount',
  });
  const n = Number(count ?? 0n);
  const ids = Array.from({length: n}, (_, i) => BigInt(i + 1));

  const {data: defs} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'catalog',
    query: {enabled: n > 0},
  });

  const {data: bal} = useReadContract({
    address: addresses.Augments,
    abi: AugmentsAbi,
    functionName: 'balanceOfBatch',
    args: [ids.map(() => address!), ids],
    query: {enabled: n > 0 && !!address},
  });

  // Only loose hardware qualifies — seating burns the token, so a seated Augment cannot be pledged
  // at all. Showing only what you actually hold spares the "why did that revert" round trip.
  const loose = ((defs as readonly {ticker: string; tier: number}[] | undefined) ?? [])
    .map((d, i) => ({
      id: i + 1,
      ticker: d.ticker,
      tier: Number(d.tier),
      qty: (bal as readonly bigint[] | undefined)?.[i] ?? 0n,
    }))
    .filter((c) => c.qty > 0n);

  return (
    <>
      <div className="kv-grid">
        <div className="kv">
          <span className="kv-k">reserve holds</span>
          <span className="kv-v">{fmt(reserveBal, 18, 0)} $AUG</span>
        </div>
        <div className="kv">
          <span className="kv-k">lent out</span>
          <span className="kv-v">{fmt(reserveOut, 18, 0)} $AUG</span>
        </div>
        <div className="kv">
          <span className="kv-k">you draw</span>
          <span className="kv-v red">half its value</span>
        </div>
        <div className="kv">
          <span className="kv-k">rate</span>
          <span className="kv-v">25% APR, simple</span>
        </div>
      </div>

      {loose.length === 0 ? (
        <div className="faint" style={{fontSize: 12, marginTop: 12}}>
          Nothing loose to pledge. Seated hardware is part of the machine — no good to him.
        </div>
      ) : (
        <div className="inv-grid" style={{marginTop: 12}}>
          {loose.map((c) => (
            <button
              key={c.id}
              className={`item-chip hw t${c.tier} ${pick === c.id ? 'picked' : ''}`}
              onClick={() => setPick(c.id)}
              onMouseEnter={() => onSay(hardware(c.ticker).flavour)}
            >
              <div>
                <div className="hwslot mono">{hardware(c.ticker).slot}</div>
                <div style={{fontSize: 13, fontWeight: 600}}>{c.ticker}</div>
                <div className="hwname">{hardware(c.ticker).name}</div>
              </div>
              <span className="qty">×{c.qty.toString()}</span>
            </button>
          ))}
        </div>
      )}

      <div className="row" style={{marginTop: 12}}>
        {!approved ? (
          <button
            className="btn primary"
            style={{flex: 1}}
            disabled={busy}
            onClick={() =>
              send('approve hardware', {
                address: addresses.Augments,
                abi: AugmentsAbi,
                functionName: 'setApprovalForAll',
                args: [addresses.Fixer, true],
              })
            }
          >
            let him hold hardware
          </button>
        ) : (
          <button
            className="btn primary"
            style={{flex: 1}}
            disabled={busy || pick === undefined}
            onClick={() => {
              onSay(line('fixer', 'augmentLoan'));
              send('borrow against hardware', {
                address: addresses.Fixer,
                abi: FixerAbi,
                functionName: 'borrowAgainstAugment',
                args: [BigInt(pick!)],
              });
            }}
          >
            {pick === undefined ? 'pick a piece' : 'borrow against it'}
          </button>
        )}
      </div>

      <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
        Interest paid back is burned rather than banked, so borrowing permanently shrinks $AUG
        supply — {fmt(burned, 18, 2)} $AUG gone this way so far. From 50% to the 70% ice threshold
        takes about 1.6 years at this rate.
      </p>
    </>
  );
}

/* ----------------------------------------------------------------- PAPER */

function LoanList({
  kind,
  count,
  needsAllowance,
  approveToken,
  approveAbi,
  onSay,
}: {
  kind: 'runner' | 'augment';
  count: number;
  needsAllowance: boolean;
  approveToken: `0x${string}`;
  approveAbi: any;
  onSay: (s: string) => void;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const isRunner = kind === 'runner';
  const ids = Array.from({length: Math.max(0, count)}, (_, i) => BigInt(i + 1));

  const {data} = useReadContracts({
    contracts: ids.flatMap((id) => [
      {
        address: addresses.Fixer,
        abi: FixerAbi,
        functionName: isRunner ? ('runnerLoans' as const) : ('augmentLoans' as const),
        args: [id],
      },
      {
        address: addresses.Fixer,
        abi: FixerAbi,
        functionName: isRunner ? ('runnerLoanLtvBps' as const) : ('augmentLoanLtvBps' as const),
        args: [id],
      },
      {
        address: addresses.Fixer,
        abi: FixerAbi,
        functionName: isRunner ? ('isRunnerLoanIceable' as const) : ('isAugmentLoanIceable' as const),
        args: [id],
      },
      {
        address: addresses.Fixer,
        abi: FixerAbi,
        functionName: isRunner ? ('runnerLoanLtvBps' as const) : ('augmentLoanDebt' as const),
        args: [id],
      },
    ]),
    query: {enabled: count > 0 && !!address},
  });

  const rows = ids
    .map((id, i) => ({
      id,
      loan: data?.[i * 4]?.result as any,
      ltv: data?.[i * 4 + 1]?.result as bigint | undefined,
      iceable: data?.[i * 4 + 2]?.result as boolean | undefined,
      debt: data?.[i * 4 + 3]?.result as bigint | undefined,
    }))
    .filter((r) => r.loan && (r.loan[0] as string)?.toLowerCase() === address?.toLowerCase());

  if (rows.length === 0) {
    return isRunner ? (
      <div className="faint" style={{fontSize: 12}}>
        No paper outstanding. Nothing of yours is sitting behind his desk.
      </div>
    ) : null;
  }

  return (
    <div style={{marginTop: isRunner ? 0 : 14}}>
      <div className="between" style={{marginBottom: 8}}>
        <h3 style={{margin: 0, fontSize: 12}}>
          {isRunner ? 'Against units' : 'Against hardware'}
        </h3>
        {needsAllowance && (
          <button
            className="btn sm primary"
            disabled={busy}
            onClick={() =>
              send('approve repayment', {
                address: approveToken,
                abi: approveAbi,
                functionName: 'approve',
                args: [addresses.Fixer, MAX_UINT],
              })
            }
          >
            approve to repay
          </button>
        )}
      </div>

      {rows.map(({id, loan, ltv, iceable, debt}) => {
        const status = Number(loan[isRunner ? 5 : 6]);
        const pct = ltv !== undefined ? Number(ltv) / 100 : 0;
        return (
          <div
            key={id.toString()}
            className={`loan-card ${status === 2 ? 'iced' : ''}`}
            onMouseEnter={() => pct >= 65 && onSay(line('fixer', 'ltvWarning'))}
          >
            <div className="between">
              <span className="mono" style={{fontSize: 12}}>
                {isRunner ? `unit #${String(loan[1]).padStart(4, '0')}` : `hardware #${loan[1]}`}
              </span>
              <span className={`tag ${status === 2 ? 'off' : status === 1 ? 'on' : ''}`}>
                {STATUS[status]}
                {iceable && status === 1 ? ' · iceable' : ''}
              </span>
            </div>

            {/* The ice line is drawn at 70% so drift is something you watch, not something you work out. */}
            <div className="ltv">
              <div className="ltv-bar">
                <div
                  className={`ltv-fill ${pct >= 70 ? 'hot' : pct >= 60 ? 'warm' : ''}`}
                  style={{width: `${Math.min(100, pct)}%`}}
                />
                <div className="ltv-ice" />
              </div>
              <div className="ltv-legend mono">
                <span>{pct}% LTV</span>
                <span>ice at 70%</span>
              </div>
            </div>

            <div className="between" style={{marginTop: 6}}>
              <span className="faint" style={{fontSize: 11}}>
                {isRunner ? `${fmt(loan[2], 18, 0)} $RUN drawn` : `${fmt(debt, 18, 2)} $AUG owed`}
              </span>
              {status !== 3 && (
                <button
                  className="btn sm"
                  disabled={busy}
                  onClick={() => {
                    onSay(line('fixer', 'repaid'));
                    send(`repay loan #${id}`, {
                      address: addresses.Fixer,
                      abi: FixerAbi,
                      functionName: isRunner ? 'repayRunnerLoan' : 'repayAugmentLoan',
                      args: [id],
                    });
                  }}
                >
                  buy it back
                </button>
              )}
            </div>
          </div>
        );
      })}

      {isRunner && (
        <p className="faint" style={{fontSize: 11, marginTop: 8, marginBottom: 0}}>
          Icing seizes control, not ownership — an Iced position stays redeemable by repaying, right
          up until the collateral is disposed of.
        </p>
      )}
    </div>
  );
}
