import {createContext, useCallback, useContext, useState, type ReactNode} from 'react';
import {useWriteContract, usePublicClient} from 'wagmi';
import {useQueryClient} from '@tanstack/react-query';
import {revertReason} from './format';
import {EXPLORER} from '../addresses';

type Status = {
  kind: 'idle' | 'pending' | 'ok' | 'error';
  label?: string;
  message?: string;
  hash?: `0x${string}`;
};

type TxContextValue = {
  status: Status;
  busy: boolean;
  send: (label: string, request: any) => Promise<boolean>;
  clear: () => void;
};

const TxContext = createContext<TxContextValue | null>(null);

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
          setStatus({kind: 'error', label, message: 'Transaction reverted on chain.', hash});
          return false;
        }

        setStatus({kind: 'ok', label, message: 'Confirmed.', hash});
        // Refresh every on-chain read in the app.
        await queryClient.invalidateQueries();
        return true;
      } catch (err) {
        setStatus({kind: 'error', label, message: revertReason(err)});
        return false;
      }
    },
    [writeContractAsync, publicClient, queryClient],
  );

  const clear = useCallback(() => setStatus({kind: 'idle'}), []);

  return (
    <TxContext.Provider value={{status, busy: status.kind === 'pending', send, clear}}>
      {children}
    </TxContext.Provider>
  );
}

export function useTx() {
  const ctx = useContext(TxContext);
  if (!ctx) throw new Error('useTx must be used inside TxProvider');
  return ctx;
}

export function TxStatusBar() {
  const {status, clear} = useTx();
  if (status.kind === 'idle') return null;

  return (
    <div className={`statusbar ${status.kind}`}>
      <div>
        <strong>{status.label}</strong> — {status.message}
        {status.hash && (
          <>
            {' '}
            <a href={`${EXPLORER}/tx/${status.hash}`} target="_blank" rel="noreferrer">
              view tx
            </a>
          </>
        )}
      </div>
      <button onClick={clear}>dismiss</button>
    </div>
  );
}
