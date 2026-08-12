'use client';

import {useEffect, useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {DropAbi, RevenueSplitterAbi, AugmentsAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt, fmtWeight, countdown} from '@/lib/format';
import {Stat, Rule, NotConnected} from '@/components/VendorShell';
import {useOwnedUnits} from '@/components/Inventory';

const PHASE = ['—', 'Weighing the collection', 'Claimable', 'Closed'];

export function DropClient() {
  const {isConnected} = useAccount();
  const {send, busy} = useTx();
  const {ids: owned} = useOwnedUnits();
  const [, tick] = useState(0);

  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const {data: dropId} = useReadContract({
    address: addresses.Drop,
    abi: DropAbi,
    functionName: 'currentDropId',
  });
  const id = (dropId as bigint | undefined) ?? 0n;

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Drop, abi: DropAbi, functionName: 'rounds', args: [id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'accumulationProgress', args: [id]},
      {
        address: addresses.RevenueSplitter,
        abi: RevenueSplitterAbi,
        functionName: 'balances',
        args: [addresses.RUN],
      },
      {address: addresses.Drop, abi: DropAbi, functionName: 'buybackPool'},
      {address: addresses.Drop, abi: DropAbi, functionName: 'skippedPool', args: [id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'dustFloor'},
      {address: addresses.Augments, abi: AugmentsAbi, functionName: 'augmentCount'},
    ],
    query: {enabled: id > 0n},
  });

  const round = data?.[0]?.result as readonly bigint[] | undefined;
  const progress = data?.[1]?.result as readonly bigint[] | undefined;
  const splits = data?.[2]?.result as readonly bigint[] | undefined;
  const buyback = data?.[3]?.result as bigint | undefined;
  const skipped = data?.[4]?.result as bigint | undefined;
  const catalogSize = Number((data?.[6]?.result as bigint | undefined) ?? 0n);

  if (!isConnected) return <NotConnected />;

  const phase = round ? Number(round[6]) : 0;
  const pool = round?.[1];
  const totalWeight = round?.[2];
  const deadline = Number(round?.[5] ?? 0n);
  const waiting = splits?.[0] ?? 0n;
  const now = Math.floor(Date.now() / 1000);
  const accDone = progress ? progress[0] > progress[1] : false;

  return (
    <>
      <section className="grid g2" style={{marginBottom: 16}}>
        <div className="panel">
          <h2 style={{marginBottom: 10}}>This week&apos;s package</h2>
          <Stat k="Waiting in the Drop bucket" v={`${fmt(waiting, 18, 0)} $RUN`} />
          <Stat k="Drop" v={`#${id.toString()} · ${PHASE[phase]}`} />
          <Stat k="Pool committed" v={`${fmt(pool, 18, 0)} $RUN`} accent />
          <Stat k="Total eligible weight" v={fmtWeight(totalWeight)} />
          <Stat
            k="Claim window closes"
            v={deadline > now ? countdown(deadline - now) : 'closed'}
            sub="one hour before the next Drop"
          />
          <Stat k="Rolled forward" v={`${fmt(skipped, 18, 0)} $RUN`} sub="unavailable tickers" />
          <Stat k="Buyback pool" v={`${fmt(buyback, 18, 0)} $RUN`} sub="from Drops nobody collected" />
        </div>

        <div className="panel">
          <h2 style={{marginBottom: 10}}>Fire a Drop</h2>
          <p className="dim" style={{fontSize: 12.5}}>
            Anyone can run these steps. Weights are read from the Stock//Runners themselves and never
            supplied by anyone, so whoever fires a Drop chooses only <em>when</em> it happens — never
            who earns from it.
          </p>

          <div className="grid" style={{gap: 8, marginTop: 12}}>
            <button
              className="btn"
              disabled={busy || waiting === 0n || phase === 1}
              onClick={() =>
                send('open a Drop', {address: addresses.Drop, abi: DropAbi, functionName: 'openDrop'})
              }
            >
              1 · open — pull the 60% bucket
            </button>
            <button
              className="btn"
              disabled={busy || phase !== 1}
              onClick={() =>
                send('weigh the collection', {
                  address: addresses.Drop,
                  abi: DropAbi,
                  functionName: 'accumulate',
                  args: [id, 50n],
                })
              }
            >
              2 · weigh {progress ? `(${progress[0]} / ${progress[1]})` : ''}
            </button>
            <button
              className="btn primary"
              disabled={busy || phase !== 1 || !accDone}
              onClick={() =>
                send('finalise the Drop', {
                  address: addresses.Drop,
                  abi: DropAbi,
                  functionName: 'finalize',
                  args: [id],
                })
              }
            >
              3 · buy — one purchase per ticker
            </button>
          </div>

          <Rule>
            At most {catalogSize || 12} purchases per Drop no matter how large the collection gets —
            all exposure to one ticker is bought in a single transaction, then divided among the bays
            running it.
          </Rule>
        </div>
      </section>

      <section className="panel">
        <h2 style={{marginBottom: 10}}>Collect</h2>
        {owned.length === 0 ? (
          <div className="dim">You hold no units.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>unit</th>
                <th>waiting</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {owned.map((u) => (
                <ClaimRow key={u} dropId={id} tokenId={u} phase={phase} />
              ))}
            </tbody>
          </table>
        )}
        <Rule>
          The Courier doesn&apos;t deliver — he holds a package and you come to collect. Assets land in
          the unit&apos;s own wallet, not yours, so its position and PnL belong to the machine and
          travel with it when it sells. Anything left when the window closes is sold to fund a $RUN
          buyback: a unit whose operator doesn&apos;t show up funds the operators who did.
        </Rule>
      </section>
    </>
  );
}

function ClaimRow({dropId, tokenId, phase}: {dropId: bigint; tokenId: number; phase: number}) {
  const {send, busy} = useTx();
  const id = BigInt(tokenId);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimable', args: [dropId, id]},
      {address: addresses.Drop, abi: DropAbi, functionName: 'claimed', args: [dropId, id]},
    ],
    query: {enabled: dropId > 0n},
  });

  const claimable = data?.[0]?.result as readonly [readonly string[], readonly bigint[]] | undefined;
  const claimed = data?.[1]?.result as boolean | undefined;
  const amounts = claimable?.[1] ?? [];
  const total = amounts.reduce((a, b) => a + b, 0n);

  return (
    <tr>
      <td>#{String(tokenId).padStart(4, '0')}</td>
      <td>
        {claimed ? (
          <span className="tag">collected</span>
        ) : total > 0n ? (
          <span className="tag on">{amounts.filter((a) => a > 0n).length} asset(s)</span>
        ) : (
          <span className="dim">nothing this cycle</span>
        )}
      </td>
      <td style={{textAlign: 'right'}}>
        <button
          className="btn sm"
          disabled={busy || phase !== 2 || claimed || total === 0n}
          onClick={() =>
            send(`collect for #${tokenId}`, {
              address: addresses.Drop,
              abi: DropAbi,
              functionName: 'claim',
              args: [dropId, id],
            })
          }
        >
          collect into unit wallet
        </button>
      </td>
    </tr>
  );
}
