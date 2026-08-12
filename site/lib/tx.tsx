'use client';

import {createContext, useCallback, useContext, useState, type ReactNode} from 'react';
import {usePublicClient, useWriteContract} from 'wagmi';
import {useQueryClient} from '@tanstack/react-query';
import {revertReason} from './errors';
import {EXPLORER} from './chain';

type Status = {
  kind: 'idle' | 'pending' | 'ok' | 'error';
  label?: string;
  message?: string;
  hash?: `0x${string}`;
};

type Ctx = {
  status: Status;
  busy: boolean;
  send: (label: string, request: any) => Promise<boolean>;
  clear: () => void;
};

const TxContext = createContext<Ctx | null>(null);

export function TxProvider({children}: {children: ReactNode}) {
  const {writeContractAsync} = useWriteContract();
  const publicClient = usePublicClient();
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<Status>({kind: 'idle'});

  const send = useCallback(
    async (label: string, request: any) => {
      setStatus({kind: 'pending', label, message: 'Confirm in your wallet…'});
      try {
        const hash = await writeContractAsync(request);
        setStatus({kind: 'pending', label, message: 'Waiting for confirmation…', hash});
        const receipt = await publicClient!.waitForTransactionReceipt({hash});
        if (receipt.status === 'reverted') {
          setStatus({kind: 'error', label, message: 'Reverted on chain.', hash});
          return false;
        }
        setStatus({kind: 'ok', label, message: 'Done.', hash});
        await queryClient.invalidateQueries();
        return true;
      } catch (err) {
        setStatus({kind: 'error', label, message: revertReason(err)});
        return false;
      }
    },
    [writeContractAsync, publicClient, queryClient],
  );

  return (
    <TxContext.Provider
      value={{status, busy: status.kind === 'pending', send, clear: () => setStatus({kind: 'idle'})}}
    >
      {children}
      <TxToast />
    </TxContext.Provider>
  );
}

export function useTx() {
  const c = useContext(TxContext);
  if (!c) throw new Error('useTx must be used inside TxProvider');
  return c;
}

function TxToast() {
  const c = useContext(TxContext)!;
  const {status, clear} = c;
  if (status.kind === 'idle') return null;

  const border =
    status.kind === 'error' ? 'var(--danger)' : status.kind === 'ok' ? 'var(--chrome)' : 'var(--sodium)';

  return (
    <div
      style={{
        position: 'fixed',
        left: 18,
        bottom: 18,
        zIndex: 300,
        maxWidth: 460,
        background: 'var(--panel)',
        border: `1px solid ${border}`,
        borderRadius: 'var(--r)',
        padding: '12px 14px',
      }}
    >
      <div className="between" style={{alignItems: 'flex-start', gap: 14}}>
        <div>
          <div
            className="mono"
            style={{fontSize: 10, letterSpacing: '0.14em', textTransform: 'uppercase', color: border}}
          >
            {status.label}
          </div>
          <div style={{fontSize: 12.5, marginTop: 4}}>{status.message}</div>
          {status.hash && (
            <a
              className="mono"
              style={{fontSize: 11}}
              href={`${EXPLORER}/tx/${status.hash}`}
              target="_blank"
              rel="noreferrer"
            >
              view transaction ↗
            </a>
          )}
        </div>
        <button className="btn sm ghost" onClick={clear}>
          ✕
        </button>
      </div>
    </div>
  );
}
