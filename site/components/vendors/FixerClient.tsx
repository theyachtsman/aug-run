'use client';

import {useState} from 'react';
import {useAccount, useReadContracts} from 'wagmi';
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
import {Stat, Rule, NotConnected} from '@/components/VendorShell';
import {useOwnedUnits} from '@/components/Inventory';

const MAX_UINT = 2n ** 256n - 1n;
const STATUS = ['—', 'Active', 'Iced', 'Closed'];

export function FixerClient() {
  const {address, isConnected} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [unit, setUnit] = useState<number | undefined>();
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

  if (!isConnected) return <NotConnected />;

  const principal = quote?.[0];
  const ethFee = quote?.[1];
  const collateral = quote?.[2];

  return (
    <>
      <section className="grid g2" style={{marginBottom: 16}}>
        <div className="panel">
          <h2>Borrow $RUN against a Runner</h2>
          <Stat k="Pool values a unit at" v={`${fmt(collateral, 18, 0)} $RUN`} />
          <Stat k="You can draw (50%)" v={`${fmt(principal, 18, 0)} $RUN`} accent />
          <Stat
            k="Upfront rate"
            v={ethFee !== undefined ? `${Number(formatEther(ethFee)).toFixed(6)} ETH` : '—'}
            sub="pegged to the pool's current sell fee"
          />
          <Stat k="Iced at" v="70% LTV, or term expiry" />
          <Stat k="Pool can lend" v={`${fmt(lendable, 18, 0)} $RUN`} sub={`${fmt(lent, 18, 0)} out now`} />

          <div className="row" style={{marginTop: 12}}>
            <select
              value={unit ?? ''}
              onChange={(e) => setUnit(e.target.value ? Number(e.target.value) : undefined)}
              style={{flex: 1}}
            >
              <option value="">pledge a unit…</option>
              {owned.map((id) => (
                <option key={id} value={id}>
                  #{String(id).padStart(4, '0')}
                </option>
              ))}
            </select>
            <input value={term} onChange={(e) => setTerm(e.target.value)} style={{width: 60}} />
            <span className="faint" style={{fontSize: 11}}>
              cycles
            </span>
            {!unitsApproved ? (
              <button
                className="btn primary"
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
                approve units
              </button>
            ) : (
              <button
                className="btn primary"
                disabled={busy || unit === undefined}
                onClick={() =>
                  send(`borrow against #${unit}`, {
                    address: addresses.Fixer,
                    abi: FixerAbi,
                    functionName: 'borrowAgainstRunner',
                    args: [BigInt(unit!), BigInt(term || '4')],
                    value: ethFee ?? 0n,
                  })
                }
              >
                borrow
              </button>
            )}
          </div>

          <Rule>
            The rate is paid once, upfront, in ETH — there is no accruing interest on a $RUN loan.
            LTV still drifts on its own, because the pool&apos;s quote moves as units are bought and
            sold. That drift is what the rate prices.
          </Rule>
        </div>

        <div className="panel">
          <h2>Borrow $AUG against an Augment</h2>
          <Stat k="Reserve holds" v={`${fmt(reserveBal, 18, 0)} $AUG`} />
          <Stat k="Lent out" v={`${fmt(reserveOut, 18, 0)} $AUG`} />
          <Stat k="You draw" v="half the Augment's value" accent />
          <Stat k="Rate" v="25% APR, simple" />
          <Stat k="Interest burned, lifetime" v={`${fmt(burned, 18, 2)} $AUG`} />

          <div className="row" style={{marginTop: 12}}>
            {!augmentsApproved ? (
              <button
                className="btn primary"
                disabled={busy}
                onClick={() =>
                  send('approve Augments', {
                    address: addresses.Augments,
                    abi: AugmentsAbi,
                    functionName: 'setApprovalForAll',
                    args: [addresses.Fixer, true],
                  })
                }
              >
                approve Augments
              </button>
            ) : (
              <AugmentBorrow />
            )}
          </div>

          <Rule>
            Only loose Augments qualify — seating burns the token, so a seated one cannot be pledged
            at all. Interest paid back is burned rather than banked, so borrowing permanently shrinks
            $AUG supply. From 50% to the 70% ice threshold takes about 1.6 years at this rate.
          </Rule>
        </div>
      </section>

      <LoanTable
        kind="runner"
        count={nRunner}
        needsAllowance={runAllowance < (principal ?? 0n)}
        approveToken={addresses.RUN}
        approveAbi={RUNAbi}
      />
      <LoanTable
        kind="augment"
        count={nAug}
        needsAllowance={augAllowance < 10_000n * 10n ** 18n}
        approveToken={addresses.AUG}
        approveAbi={AUGAbi}
      />
    </>
  );
}

function AugmentBorrow() {
  const {send, busy} = useTx();
  const [pick, setPick] = useState('1');
  return (
    <>
      <input value={pick} onChange={(e) => setPick(e.target.value)} style={{width: 70}} />
      <span className="faint" style={{fontSize: 11}}>
        augment id
      </span>
      <button
        className="btn primary"
        disabled={busy}
        onClick={() =>
          send('borrow against an Augment', {
            address: addresses.Fixer,
            abi: FixerAbi,
            functionName: 'borrowAgainstAugment',
            args: [BigInt(pick || '1')],
          })
        }
      >
        borrow
      </button>
    </>
  );
}

function LoanTable({
  kind,
  count,
  needsAllowance,
  approveToken,
  approveAbi,
}: {
  kind: 'runner' | 'augment';
  count: number;
  needsAllowance: boolean;
  approveToken: `0x${string}`;
  approveAbi: any;
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

  if (rows.length === 0) return null;

  return (
    <section className="panel" style={{marginBottom: 14}}>
      <div className="between" style={{marginBottom: 10}}>
        <h2>Your {kind} loans</h2>
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

      <table>
        <thead>
          <tr>
            <th>loan</th>
            <th>collateral</th>
            <th>{isRunner ? 'principal' : 'debt'}</th>
            <th>LTV</th>
            <th>state</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map(({id, loan, ltv, iceable, debt}) => {
            const status = Number(loan[isRunner ? 5 : 6]);
            return (
              <tr key={id.toString()}>
                <td>#{id.toString()}</td>
                <td>{isRunner ? `unit #${loan[1]}` : `augment #${loan[1]}`}</td>
                <td>{isRunner ? fmt(loan[2], 18, 0) : fmt(debt, 18, 2)}</td>
                <td style={{color: (ltv ?? 0n) >= 6500n ? 'var(--danger)' : undefined}}>
                  {ltv !== undefined ? `${Number(ltv) / 100}%` : '—'}
                </td>
                <td>
                  <span className={`tag ${status === 2 ? 'off' : status === 1 ? 'on' : ''}`}>
                    {STATUS[status]}
                  </span>
                  {iceable && status === 1 && <span className="tag off"> iceable</span>}
                </td>
                <td style={{textAlign: 'right'}}>
                  {status !== 3 && (
                    <button
                      className="btn sm"
                      disabled={busy}
                      onClick={() =>
                        send(`repay loan #${id}`, {
                          address: addresses.Fixer,
                          abi: FixerAbi,
                          functionName: isRunner ? 'repayRunnerLoan' : 'repayAugmentLoan',
                          args: [id],
                        })
                      }
                    >
                      repay
                    </button>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <Rule>
        Icing seizes control, not ownership — an Iced position stays redeemable by repaying, right up
        until the collateral is disposed of.
      </Rule>
    </section>
  );
}
