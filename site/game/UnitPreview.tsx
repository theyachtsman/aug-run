'use client';

import {useReadContracts} from 'wagmi';
import {addresses} from '@/lib/addresses';
import {StockRunnerAbi, RipperdocAbi, AugmentsAbi} from '@/lib/generated/abis';
import {fmtWeight} from '@/lib/format';
import {ArtSlot, modelName} from '@/components/ArtSlot';
import {hardware} from './augmentNames';

/**
 * The unit on display, centre stage.
 *
 * Both shops keep this slot reserved so the thing you are trading is always the largest object on
 * screen — the way a shop in an RPG shows you the item, not a row of text. Clicking any unit in a
 * menu swaps what stands here.
 *
 * When nothing is selected it holds the frame rather than collapsing, so the layout never jumps as
 * you click through a list.
 */
export function UnitPreview({
  tokenId,
  caption,
}: {
  tokenId?: number;
  caption?: string;
}) {
  const id = BigInt(tokenId ?? 0);
  const enabled = tokenId !== undefined;

  const {data} = useReadContracts({
    contracts: [
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'modelOf', args: [id]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'bayCountOf', args: [id]},
      {address: addresses.Ripperdoc, abi: RipperdocAbi, functionName: 'unitWeight', args: [id]},
      {
        address: addresses.Ripperdoc,
        abi: RipperdocAbi,
        functionName: 'unitEligibleWeight',
        args: [id],
      },
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'getBay', args: [id, 0]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'getBay', args: [id, 1]},
      {address: addresses.StockRunner, abi: StockRunnerAbi, functionName: 'getBay', args: [id, 2]},
      {
        address: addresses.StockRunner,
        abi: StockRunnerAbi,
        functionName: 'calibrationCountOf',
        args: [id],
      },
    ],
    query: {enabled},
  });

  const model = data?.[0]?.result as number | undefined;
  const bays = Number((data?.[1]?.result as number | undefined) ?? 0);
  const weight = data?.[2]?.result as bigint | undefined;
  const eligible = data?.[3]?.result as bigint | undefined;
  const calibrations = Number((data?.[7]?.result as number | undefined) ?? 0);

  const seated = [4, 5, 6]
    .map((i) => data?.[i]?.result as {augmentId: bigint; tier: number} | undefined)
    .filter((b): b is {augmentId: bigint; tier: number} => !!b && b.augmentId > 0n);

  return (
    <div className="preview">
      <div className="preview-art">
        <ArtSlot
          label={enabled ? modelName(model) : 'NO UNIT'}
          hint={enabled ? `#${String(tokenId).padStart(4, '0')}` : 'select one'}
          ratio="3 / 4"
        />
      </div>

      {enabled ? (
        <>
          <div className="preview-id mono">#{String(tokenId).padStart(4, '0')}</div>
          <div className="preview-model">{modelName(model)}</div>

          <div className="preview-stats">
            <span className="tag">
              {bays} bay{bays === 1 ? '' : 's'}
            </span>
            <span className="tag on">{fmtWeight(weight)}</span>
            {(eligible ?? 0n) === 0n ? (
              <span className="tag warn">idle</span>
            ) : (
              <span className="tag on">earning</span>
            )}
            {calibrations > 0 && <span className="tag">{calibrations} cal</span>}
          </div>

          {seated.length > 0 ? (
            <div className="preview-load">
              {seated.map((b, i) => (
                <SeatedBadge key={i} augmentId={b.augmentId} tier={b.tier} />
              ))}
            </div>
          ) : (
            <div className="faint" style={{fontSize: 11, marginTop: 8}}>
              Nothing installed — factory default.
            </div>
          )}

          {caption && (
            <div className="faint" style={{fontSize: 11, marginTop: 10}}>
              {caption}
            </div>
          )}
        </>
      ) : (
        <div className="faint" style={{fontSize: 12, marginTop: 12, textAlign: 'center'}}>
          {caption ?? 'Click a unit to inspect it.'}
        </div>
      )}
    </div>
  );
}

function SeatedBadge({augmentId, tier}: {augmentId: bigint; tier: number}) {
  const {data} = useReadContracts({
    contracts: [
      {address: addresses.Augments, abi: AugmentsAbi, functionName: 'tickerOf', args: [augmentId]},
    ],
  });
  const ticker = (data?.[0]?.result as string | undefined) ?? '···';
  const hw = hardware(ticker);

  return (
    <div className={`preview-badge t${tier}`} title={hw.flavour}>
      <div className="mono" style={{fontSize: 8.5, letterSpacing: '0.14em', opacity: 0.75}}>
        {hw.slot}
      </div>
      <div style={{fontSize: 11, fontWeight: 600, lineHeight: 1.2}}>{ticker}</div>
      <div className="faint" style={{fontSize: 9, lineHeight: 1.25}}>
        {hw.name}
      </div>
    </div>
  );
}
