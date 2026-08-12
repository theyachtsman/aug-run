import React from 'react';
import ReactDOM from 'react-dom/client';
import {WagmiProvider} from 'wagmi';
import {QueryClient, QueryClientProvider} from '@tanstack/react-query';

import {config} from './chain';
import {TxProvider} from './lib/useTx';
import App from './App';
import './styles.css';

const queryClient = new QueryClient({
  defaultOptions: {queries: {refetchOnWindowFocus: false, retry: 1}},
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <TxProvider>
          <App />
        </TxProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>,
);
