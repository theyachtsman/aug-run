'use client';

import {useState} from 'react';
import {useAccount, useReadContract, useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {ChopShopAbi, MockUSDGAbi, AugmentsAbi} from '@/lib/generated/abis';
import {useTx} from '@/lib/tx';
import {fmt} from '@/lib/format';
import {line} from '../vendors';
import {hardware} from '../augmentNames';
import {CentrePanel, Line} from '../CentrePanel';

const MAX_UINT = 2n ** 256n - 1n;
const DP = 6; // USDG has 6 decimals, matching the real Global Dollar
const ROLL_STATE = ['—', 'Committed', 'Won', 'Lost', 'Refunded'];

const usdg = (v: string) => {
  const n = Number(v || '0');
  return Number.isFinite(n) ? BigInt(Math.floor(n * 10 ** DP)) : 0n;
};

/**
 * The Scrapper's table.
 *
 * The whole shop turns on one counter-intuitive rule — backing an item heavily makes it *harder*
 * to win — so the odds ring is the centre of the room and it moves live as you drag the backing
 * around. Seeing your own odds collapse as you protect your item teaches the mechanic in a way no
 * amount of explanatory text does.
 */
export function ChopShopScene({onSay}: {onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const [tab, setTab] = useState<'list' | 'table' | 'rolls'>('table');
  const [augId, setAugId] = useState<number | undefined>();
  const [declared, setDeclared] = useState('1000');
  const [backing, setBacking] = useState('1000');
  const [inspect, setInspect] = useState<bigint | undefined>();

  const dv = usdg(declared);
  const bk = usdg(backing);

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextListingId'},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'nextRollId'},
      {address: addresses.USDG, abi: MockUSDGAbi, functionName: 'balanceOf', args: [address!]},
      {
        address: addresses.USDG,
        abi: MockUSDGAbi,
        functionName: 'allowance',
        args: [address!, addresses.ChopShop],
      },
      {
        address: addresses.Augments,
        abi: AugmentsAbi,
        functionName: 'isApprovedForAll',
        args: [address!, addresses.ChopShop],
      },
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'winProbabilityBps', args: [dv, bk]},
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'entryCost', args: [dv, bk]},
    ],
    query: {enabled: !!address},
  });

  const nListings = Number((data?.[0]?.result as bigint | undefined) ?? 1n) - 1;
  const nRolls = Number((data?.[1]?.result as bigint | undefined) ?? 1n) - 1;
  const balance = data?.[2]?.result as bigint | undefined;
  const allowance = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const augApproved = (data?.[4]?.result as boolean | undefined) ?? false;
  const myP = data?.[5]?.result as bigint | undefined;
  const myEntry = data?.[6]?.result as bigint | undefined;

  const floor = (dv * 2500n) / 10_000n;
  const belowFloor = bk < floor;
  const needsUsdg = allowance < 10_000n * 10n ** BigInt(DP);

  const listingIds = Array.from({length: Math.max(0, nListings)}, (_, i) => BigInt(i + 1));

  const {data: ld} = useReadContracts({
    contracts: listingIds.flatMap((id) => [
      {address: addresses.ChopShop, abi: ChopShopAbi, functionName: 'listings' as const, args: [id]},
      {
        address: addresses.ChopShop,
        abi: ChopShopAbi,
        functionName: 'listingEntryCost' as const,
        args: [id],
      },
    ]),
    query: {enabled: listingIds.length > 0},
  });

  const table = listingIds
    .map((id, i) => {
      const l = ld?.[i * 2]?.result as any;
      const cost = ld?.[i * 2 + 1]?.result as bigint | undefined;
      if (!l) return null;
      const v = l[4] as bigint;
      const b = l[5] as bigint;
      return {
        id,
        dv: v,
        bk: b,
        cost,
        open: l[7] as boolean,
        settled: l[8] as boolean,
        pct: v > 0n ? Number((v * 10_000n) / (v + b)) / 100 : 0,
      };
    })
    .filter((x): x is NonNullable<typeof x> => !!x);

  // The ring shows whichever item you are looking at: a listing on the table, or the one you are
  // building on the list tab.
  const shown = tab === 'list' ? null : table.find((t) => t.id === inspect);
  const ringPct = shown ? shown.pct : myP !== undefined ? Number(myP) / 100 : 0;
  const ringDv = shown ? shown.dv : dv;
  const ringBk = shown ? shown.bk : bk;
  const ringEntry = shown ? shown.cost : myEntry;

  return (
    <>
      <CentrePanel
        title={shown ? `LISTING #${shown.id}` : 'YOUR LISTING'}
        sub={shown ? (shown.settled ? 'settled' : shown.open ? 'open' : 'rolling') : 'not yet on the table'}
      >
        <OddsRing pct={ringPct} />

        <Line k="declared value" v={`${fmt(ringDv, DP, 0)} USDG`} />
        <Line k="backed with" v={`${fmt(ringBk, DP, 0)} USDG`} />
        <Line k="entry costs" v={`${fmt(ringEntry, DP, 2)} USDG`} tone="sodium" />

        <p className="faint centre-note">
          {ringPct >= 50
            ? 'Backed light. Everyone fancies their chances — including you, when you play someone else’s.'
            : ringPct >= 25
              ? 'Balanced. The table will take an interest.'
              : 'Backed heavy. Hard to win, and priced accordingly.'}
        </p>
      </CentrePanel>

      <div className="shop-menu">
        <div className="between" style={{marginBottom: 10}}>
          <h3 style={{margin: 0}}>The Table</h3>
          <span className="mono faint" style={{fontSize: 11}}>
            {fmt(balance, DP, 2)} USDG
          </span>
        </div>

        <div className="tabs">
          <button
            className={`tab ${tab === 'table' ? 'active' : ''}`}
            onClick={() => setTab('table')}
            onMouseEnter={() => onSay(line('chopshop', 'enter'))}
          >
            On the table
          </button>
          <button
            className={`tab ${tab === 'list' ? 'active' : ''}`}
            onClick={() => setTab('list')}
            onMouseEnter={() => onSay(line('chopshop', 'enter'))}
          >
            Put one up
          </button>
          <button
            className={`tab ${tab === 'rolls' ? 'active' : ''}`}
            onClick={() => setTab('rolls')}
            onMouseEnter={() => onSay(line('chopshop', 'rolled'))}
          >
            Your rolls
          </button>
        </div>

        {needsUsdg && (
          <div className="row" style={{marginBottom: 10}}>
            <button
              className="btn primary"
              style={{flex: 1}}
              disabled={busy}
              onClick={() =>
                send('approve USDG', {
                  address: addresses.USDG,
                  abi: MockUSDGAbi,
                  functionName: 'approve',
                  args: [addresses.ChopShop, MAX_UINT],
                })
              }
            >
              approve USDG
            </button>
            <button
              className="btn sm ghost"
              disabled={busy}
              onClick={() =>
                send('mint test USDG', {
                  address: addresses.USDG,
                  abi: MockUSDGAbi,
                  functionName: 'mint',
                  args: [address!, 100_000n * 10n ** BigInt(DP)],
                })
              }
            >
              get test USDG
            </button>
          </div>
        )}

        {tab === 'table' && (
          <>
            {table.length === 0 ? (
              <div className="faint" style={{fontSize: 12}}>
                Nothing on the table. Come back when the Scrapper finds something worth risking.
              </div>
            ) : (
              <div className="grid" style={{gap: 6}}>
                {table.map((t) => (
                  <button
                    key={t.id.toString()}
                    className={`table-row ${inspect === t.id ? 'selected' : ''} ${
                      !t.open || t.settled ? 'closed' : ''
                    }`}
                    onClick={() => setInspect(t.id)}
                  >
                    <span className="mono" style={{fontSize: 12}}>
                      #{t.id.toString()}
                    </span>
                    <span className="odds">{t.pct}%</span>
                    <span className="faint" style={{fontSize: 11}}>
                      {fmt(t.dv, DP, 0)} value
                    </span>
                    <span className="mono" style={{fontSize: 11}}>
                      {fmt(t.cost, DP, 0)} in
                    </span>
                  </button>
                ))}
              </div>
            )}

            {inspect !== undefined && (
              <button
                className="btn primary"
                style={{width: '100%', marginTop: 10}}
                disabled={busy || !table.find((t) => t.id === inspect)?.open}
                onClick={() => {
                  onSay(line('chopshop', 'rolled'));
                  send(`roll for #${inspect}`, {
                    address: addresses.ChopShop,
                    abi: ChopShopAbi,
                    functionName: 'roll',
                    args: [inspect],
                  });
                }}
              >
                roll for #{inspect.toString()}
              </button>
            )}

            <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
              Rolling commits. Settling reads a block that did not exist when you committed — so
              nobody, the house included, can know the outcome in advance.
            </p>
          </>
        )}

        {tab === 'list' && (
          <ListItem
            augId={augId}
            setAugId={setAugId}
            declared={declared}
            setDeclared={setDeclared}
            backing={backing}
            setBacking={setBacking}
            belowFloor={belowFloor}
            floor={floor}
            approved={augApproved}
            dv={dv}
            bk={bk}
            onSay={onSay}
          />
        )}

        {tab === 'rolls' && <YourRolls nRolls={nRolls} onSay={onSay} />}
      </div>
    </>
  );
}

/* ------------------------------------------------------------------ RING */

/** Odds as a ring rather than a number — it moves as you drag the backing, which is the lesson. */
function OddsRing({pct}: {pct: number}) {
  const r = 62;
  const c = 2 * Math.PI * r;
  const filled = (Math.min(100, Math.max(0, pct)) / 100) * c;

  return (
    <div className="ring-wrap">
      <svg viewBox="0 0 160 160" className="ring">
        <circle cx="80" cy="80" r={r} className="ring-track" />
        <circle
          cx="80"
          cy="80"
          r={r}
          className={`ring-fill ${pct >= 50 ? 'hot' : pct >= 25 ? 'warm' : ''}`}
          strokeDasharray={`${filled} ${c}`}
          transform="rotate(-90 80 80)"
        />
      </svg>
      <div className="ring-label">
        <div className="ring-pct">{pct.toFixed(1)}%</div>
        <div className="ring-sub mono">CHANCE TO WIN</div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ LIST */

function ListItem({
  augId,
  setAugId,
  declared,
  setDeclared,
  backing,
  setBacking,
  belowFloor,
  floor,
  approved,
  dv,
  bk,
  onSay,
}: {
  augId?: number;
  setAugId: (n: number) => void;
  declared: string;
  setDeclared: (s: string) => void;
  backing: string;
  setBacking: (s: string) => void;
  belowFloor: boolean;
  floor: bigint;
  approved: boolean;
  dv: bigint;
  bk: bigint;
  onSay: (s: string) => void;
}) {
  const {address} = useAccount();
  const {send, busy} = useTx();

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

  const loose = ((defs as readonly {ticker: string; tier: number}[] | undefined) ?? [])
    .map((d, i) => ({
      id: i + 1,
      ticker: d.ticker,
      tier: Number(d.tier),
      qty: (bal as readonly bigint[] | undefined)?.[i] ?? 0n,
    }))
    .filter((c) => c.qty > 0n);

  // The floor is a percentage of declared value, so the slider's ceiling has to move with it —
  // otherwise a high-value item's legal range collapses into the first pixel of travel.
  const declaredNum = Number(declared || '0');
  const maxBacking = Math.max(declaredNum * 4, 100);

  return (
    <>
      {loose.length === 0 ? (
        <div className="faint" style={{fontSize: 12}}>
          You hold no loose hardware. Seated pieces are burned into their unit and cannot be listed.
        </div>
      ) : (
        <div className="inv-grid">
          {loose.map((c) => (
            <button
              key={c.id}
              className={`item-chip hw t${c.tier} ${augId === c.id ? 'picked' : ''}`}
              onClick={() => setAugId(c.id)}
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

      <div className="field" style={{marginTop: 12}}>
        <label className="field-l mono">DECLARED VALUE</label>
        <div className="row">
          <input value={declared} onChange={(e) => setDeclared(e.target.value)} style={{flex: 1}} />
          <span className="faint" style={{fontSize: 11}}>
            USDG
          </span>
        </div>
      </div>

      <div className="field">
        <label className="field-l mono">
          YOUR BACKING · floor {fmt(floor, DP, 0)}
        </label>
        <input
          type="range"
          min={0}
          max={maxBacking}
          step={Math.max(1, Math.round(maxBacking / 200))}
          value={Math.min(Number(backing || '0'), maxBacking)}
          onChange={(e) => setBacking(e.target.value)}
          className="slider"
        />
        <div className="row">
          <input value={backing} onChange={(e) => setBacking(e.target.value)} style={{flex: 1}} />
          <span className="faint" style={{fontSize: 11}}>
            USDG
          </span>
        </div>
      </div>

      {belowFloor && (
        <div className="notice hot" style={{marginTop: 8, padding: '9px 11px'}}>
          <span style={{fontSize: 11.5}}>
            Backing must be at least 25% of declared value — a heavily-built item cannot be listed at
            trivial backing.
          </span>
        </div>
      )}

      <button
        className="btn primary"
        style={{width: '100%', marginTop: 12}}
        disabled={busy || belowFloor || (approved && augId === undefined)}
        onClick={() => {
          if (!approved) {
            send('approve hardware', {
              address: addresses.Augments,
              abi: AugmentsAbi,
              functionName: 'setApprovalForAll',
              args: [addresses.ChopShop, true],
            });
            return;
          }
          onSay(line('chopshop', 'listed'));
          send('put it on the table', {
            address: addresses.ChopShop,
            abi: ChopShopAbi,
            functionName: 'list',
            args: [1, addresses.Augments, BigInt(augId!), dv, bk],
          });
        }}
      >
        {!approved ? 'let him hold hardware' : augId === undefined ? 'pick a piece' : 'put it on the table'}
      </button>

      <p className="faint" style={{fontSize: 11, marginTop: 10, marginBottom: 0}}>
        <strong>The less you back it with, the better everyone&apos;s odds.</strong> Declared value is
        self-policing — understate it and your item is easy to win; overstate it and nobody plays.
      </p>
    </>
  );
}

/* ----------------------------------------------------------------- ROLLS */

function YourRolls({nRolls, onSay}: {nRolls: number; onSay: (s: string) => void}) {
  const {address} = useAccount();
  const {send, busy} = useTx();
  const rollIds = Array.from({length: Math.max(0, nRolls)}, (_, i) => BigInt(i + 1));

  const {data} = useReadContracts({
    contracts: rollIds.map((id) => ({
      address: addresses.ChopShop,
      abi: ChopShopAbi,
      functionName: 'rolls' as const,
      args: [id],
    })),
    query: {enabled: rollIds.length > 0},
  });

  const mine = rollIds
    .map((id, i) => ({id, r: data?.[i]?.result as any}))
    .filter(({r}) => r && (r[1] as string)?.toLowerCase() === address?.toLowerCase());

  if (mine.length === 0) {
    return (
      <div className="faint" style={{fontSize: 12}}>
        You have not played. The Scrapper notices things like that.
      </div>
    );
  }

  return (
    <>
      {mine.map(({id, r}) => {
        const state = Number(r[5]);
        return (
          <div key={id.toString()} className="loan-card">
            <div className="between">
              <span className="mono" style={{fontSize: 12}}>
                roll #{id.toString()} · listing #{(r[0] as bigint).toString()}
              </span>
              <span className={`tag ${state === 2 ? 'on' : state === 3 ? 'off' : ''}`}>
                {ROLL_STATE[state]}
              </span>
            </div>

            <div className="faint" style={{fontSize: 11, marginTop: 4}}>
              {fmt(r[2] as bigint, DP, 2)} USDG in
            </div>

            {state === 1 && (
              <div className="row" style={{marginTop: 8}}>
                <button
                  className="btn sm primary"
                  style={{flex: 1}}
                  disabled={busy}
                  onClick={() =>
                    send(`settle roll #${id}`, {
                      address: addresses.ChopShop,
                      abi: ChopShopAbi,
                      functionName: 'resolve',
                      args: [id],
                    })
                  }
                >
                  settle it
                </button>
                <button
                  className="btn sm ghost"
                  disabled={busy}
                  onClick={() =>
                    send(`refund roll #${id}`, {
                      address: addresses.ChopShop,
                      abi: ChopShopAbi,
                      functionName: 'refundExpiredRoll',
                      args: [id],
                    })
                  }
                >
                  refund
                </button>
              </div>
            )}

            {state === 2 && (
              <div className="row" style={{marginTop: 8}}>
                {(
                  [
                    ['take the item', 0],
                    ['cash out 85%', 1],
                    ['convert 90%', 2],
                  ] as const
                ).map(([label, mode]) => (
                  <button
                    key={mode}
                    className="btn sm"
                    disabled={busy}
                    onMouseEnter={() => onSay(line('chopshop', 'won'))}
                    onClick={() =>
                      send(`claim roll #${id}`, {
                        address: addresses.ChopShop,
                        abi: ChopShopAbi,
                        functionName: 'claim',
                        args: [id, mode],
                      })
                    }
                  >
                    {label}
                  </button>
                ))}
              </div>
            )}
          </div>
        );
      })}

      <p className="faint" style={{fontSize: 11, marginTop: 8, marginBottom: 0}}>
        Settling is permissionless. A roll that outruns its ~25 second window refunds in full.
      </p>
    </>
  );
}
