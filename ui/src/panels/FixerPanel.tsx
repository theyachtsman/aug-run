import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {formatEther} from 'viem';
import {addresses} from '../addresses';
import {
  FixerAbi,
  BlackMarketAbi,
  ProtocolReserveAbi,
  StockRunnerAbi,
  AugmentsAbi,
  RUNAbi,
  AUGAbi,
} from '../generated/abis';
import {useTx} from '../lib/useTx';
import {fmt} from '../lib/format';
import {useOwnedUnits} from './UnitsPanel';
import {useCatalog} from './ShopPanel';

const MAX_UINT = 2n ** 256n - 1n;

export function FixerPanel() {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const {ids: ownedIds} = useOwnedUnits();
  const catalog = useCatalog();

  const [unitPick, setUnitPick] = useState<number | undefined>();
  const [term, setTerm] = useState('4');
  const [augPick, setAugPick] = useState<number>(1);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Fixer, abi: FixerAbi, functionName: 'quoteRunnerLoan'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'lendableRun'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'totalLent'},
      {address: addresses.BlackMarket, abi: BlackMarketAbi, functionName: 'sellFeeBps'},
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
      {
        address: addresses.RUN,
        abi: RUNAbi,
        functionName: 'allowance',
        args: [address!, addresses.Fixer],
      },
      {
        address: addresses.AUG,
        abi: AUGAbi,
        functionName: 'allowance',
        args: [address!, addresses.Fixer],
      },
    ],
    query: {enabled: !!address},
  });

  const quote = data?.[0]?.result as readonly bigint[] | undefined;
  const lendable = data?.[1]?.result as bigint | undefined;
  const totalLent = data?.[2]?.result as bigint | undefined;
  const sellFeeBps = data?.[3]?.result as bigint | undefined;
  const reserveBalance = data?.[4]?.result as bigint | undefined;
  const reserveOut = data?.[5]?.result as bigint | undefined;
  const nextRunnerLoan = Number((data?.[6]?.result as bigint | undefined) ?? 1n);
  const nextAugLoan = Number((data?.[7]?.result as bigint | undefined) ?? 1n);
  const interestBurned = data?.[8]?.result as bigint | undefined;
  const runnerApproved = (data?.[9]?.result as boolean | undefined) ?? false;
  const augmentsApproved = (data?.[10]?.result as boolean | undefined) ?? false;
  const runAllowance = (data?.[11]?.result as bigint | undefined) ?? 0n;
  const augAllowance = (data?.[12]?.result as bigint | undefined) ?? 0n;

  const principal = quote?.[0];
  const ethFee = quote?.[1];
  const collateral = quote?.[2];

  return (
    <div className="panel">
      <h2>The Fixer — borrow against what you own</h2>

      <div className="grid2" style={{gap: 8}}>
        <div>
          <div className="spread">
            <span className="dim">pool lendable</span>
            <span className="mono">{fmt(lendable, 18, 0)} $RUN</span>
          </div>
          <div className="spread">
            <span className="dim">currently lent</span>
            <span className="mono">{fmt(totalLent, 18, 0)} $RUN</span>
          </div>
        </div>
        <div>
          <div className="spread">
            <span className="dim">reserve balance</span>
            <span className="mono">{fmt(reserveBalance, 18, 0)} $AUG</span>
          </div>
          <div className="spread">
            <span className="dim">reserve lent out</span>
            <span className="mono">{fmt(reserveOut, 18, 0)} $AUG</span>
          </div>
        </div>
      </div>

      {/* ------------------------------------------------ RUNNER LOANS */}
      <h3>Borrow $RUN against a Stock//Runner</h3>
      <div className="grid2" style={{gap: 8}}>
        <div>
          <div className="spread">
            <span className="dim">pool values a unit at</span>
            <span className="mono">{fmt(collateral, 18, 0)} $RUN</span>
          </div>
          <div className="spread">
            <span className="dim">you can draw (50%)</span>
            <span className="mono">{fmt(principal, 18, 0)} $RUN</span>
          </div>
        </div>
        <div>
          <div className="spread">
            <span className="dim">upfront rate ({Number(sellFeeBps ?? 0n) / 100}%)</span>
            <span className="mono">
              {ethFee !== undefined ? `${Number(formatEther(ethFee)).toFixed(6)} ETH` : '—'}
            </span>
          </div>
          <div className="spread">
            <span className="dim">Iced at</span>
            <span className="mono">70% LTV or term expiry</span>
          </div>
        </div>
      </div>

      <div className="row" style={{marginTop: 10}}>
        <select
          value={unitPick ?? ''}
          onChange={(e) => setUnitPick(e.target.value ? Number(e.target.value) : undefined)}
        >
          <option value="">select a unit…</option>
          {ownedIds.map((id) => (
            <option key={id} value={id}>
              #{id}
            </option>
          ))}
        </select>
        <input value={term} onChange={(e) => setTerm(e.target.value)} style={{width: 70}} />
        <span className="dim">cycles (1–52)</span>

        {!runnerApproved ? (
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve units for the Fixer', {
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
            className="primary"
            disabled={busy || unitPick === undefined}
            onClick={() =>
              send(`borrow against #${unitPick}`, {
                address: addresses.Fixer,
                abi: FixerAbi,
                functionName: 'borrowAgainstRunner',
                args: [BigInt(unitPick!), BigInt(term || '4')],
                value: ethFee ?? 0n,
              })
            }
          >
            borrow {fmt(principal, 18, 0)} $RUN
          </button>
        )}
      </div>
      <div className="note">
        The rate is paid once, upfront, in ETH — pegged to the Black Market's current sell fee tier.
        There is no accruing interest on a $RUN loan. LTV still drifts, because the pool's quote moves
        as units are bought and sold.
      </div>

      <LoanList
        kind="runner"
        count={nextRunnerLoan - 1}
        needsAllowance={runAllowance < (principal ?? 0n)}
        onApprove={() =>
          send('approve $RUN for the Fixer', {
            address: addresses.RUN,
            abi: RUNAbi,
            functionName: 'approve',
            args: [addresses.Fixer, MAX_UINT],
          })
        }
      />

      {/* ----------------------------------------------- AUGMENT LOANS */}
      <h3>Borrow $AUG against an unused Augment</h3>
      <div className="row">
        <select value={augPick} onChange={(e) => setAugPick(Number(e.target.value))}>
          {catalog.map((c) => (
            <option key={c.id} value={c.id}>
              {c.ticker} T{c.tier} · draw {Number(c.price / 10n ** 18n) / 2} $AUG
              {c.loose > 0n ? ` · ${c.loose} loose` : ' · none loose'}
            </option>
          ))}
        </select>
        {!augmentsApproved ? (
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('approve Augments for the Fixer', {
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
          <button
            className="primary"
            disabled={busy}
            onClick={() =>
              send('borrow against Augment', {
                address: addresses.Fixer,
                abi: FixerAbi,
                functionName: 'borrowAgainstAugment',
                args: [BigInt(augPick)],
              })
            }
          >
            borrow
          </button>
        )}
      </div>
      <div className="note">
        Draw half the Augment's $AUG value at a fixed 25% APR, funded from the protocol reserve. Only
        loose Augments qualify — seating burns the token, so a seated one cannot be pledged at all.
        Interest paid back is <strong>burned</strong>: lifetime{' '}
        <span className="mono">{fmt(interestBurned, 18, 2)} $AUG</span>.
      </div>

      <LoanList
        kind="augment"
        count={nextAugLoan - 1}
        needsAllowance={augAllowance < 10_000n * 10n ** 18n}
        onApprove={() =>
          send('approve $AUG for the Fixer', {
            address: addresses.AUG,
            abi: AUGAbi,
            functionName: 'approve',
            args: [addresses.Fixer, MAX_UINT],
          })
        }
      />
    </div>
  );
}

function LoanList({
  kind,
  count,
  needsAllowance,
  onApprove,
}: {
  kind: 'runner' | 'augment';
  count: number;
  needsAllowance: boolean;
  onApprove: () => void;
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
        functionName: isRunner
          ? ('isRunnerLoanIceable' as const)
          : ('isAugmentLoanIceable' as const),
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

  if (count <= 0) return <div className="note">No {kind} loans opened yet.</div>;

  const rows = ids.map((id, i) => {
    const loan = data?.[i * 4]?.result as any;
    const ltv = data?.[i * 4 + 1]?.result as bigint | undefined;
    const iceable = data?.[i * 4 + 2]?.result as boolean | undefined;
    const debt = data?.[i * 4 + 3]?.result as bigint | undefined;
    return {id, loan, ltv, iceable, debt};
  });

  const mine = rows.filter(
    (r) => r.loan && (r.loan[0] as string)?.toLowerCase() === address?.toLowerCase(),
  );

  return (
    <>
      {needsAllowance && mine.length > 0 && (
        <div className="row" style={{marginTop: 8}}>
          <button className="primary" disabled={busy} onClick={onApprove}>
            approve repayment token
          </button>
          <span className="note">needed before you can repay</span>
        </div>
      )}
      <table style={{marginTop: 8}}>
        <thead>
          <tr>
            <th>loan</th>
            <th>collateral</th>
            <th>{isRunner ? 'principal' : 'debt'}</th>
            <th>LTV</th>
            <th>status</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {mine.map(({id, loan, ltv, iceable, debt}) => {
            const status = Number(loan[isRunner ? 5 : 6]);
            const statusLabel = ['—', 'Active', 'Iced', 'Closed'][status] ?? '—';
            return (
              <tr key={id.toString()}>
                <td className="mono">#{id.toString()}</td>
                <td className="mono">
                  {isRunner ? `unit #${loan[1]}` : `augment #${loan[1]}`}
                </td>
                <td className="mono">
                  {isRunner ? fmt(loan[2], 18, 0) : fmt(debt, 18, 2)}
                </td>
                <td className="mono">
                  {ltv !== undefined ? `${Number(ltv) / 100}%` : '—'}
                </td>
                <td>
                  <span className={`tag ${status === 2 ? 'locked' : status === 1 ? 'eligible' : ''}`}>
                    {statusLabel}
                  </span>
                  {iceable && status === 1 && <span className="tag locked"> iceable</span>}
                </td>
                <td>
                  {status !== 3 && (
                    <button
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
    </>
  );
}
