'use client';

import {useState, type ReactNode} from 'react';
import {WagmiProvider} from 'wagmi';
import {QueryClient, QueryClientProvider} from '@tanstack/react-query';
import {config} from '@/lib/chain';
import {TxProvider} from '@/lib/tx';

export function Providers({children}: {children: ReactNode}) {
  // One client per browser session; created lazily so the server render doesn't share state.
  const [queryClient] = useState(
    () => new QueryClient({defaultOptions: {queries: {refetchOnWindowFocus: false, retry: 1}}}),
  );

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <TxProvider>{children}</TxProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
