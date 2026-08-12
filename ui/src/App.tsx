import {useAccount, useConnect, useDisconnect, useSwitchChain} from 'wagmi';
import {robinhoodTestnet} from './chain';
import {addresses, EXPLORER} from './addresses';
import {TxStatusBar} from './lib/useTx';
import {shortAddr} from './lib/format';
import {WalletPanel} from './panels/WalletPanel';
import {CyclePanel} from './panels/CyclePanel';
import {MintPanel} from './panels/MintPanel';
import {ShopPanel} from './panels/ShopPanel';
import {UnitsPanel} from './panels/UnitsPanel';
import {BlackMarketPanel} from './panels/BlackMarketPanel';
import {TerminalPanel} from './panels/TerminalPanel';
import {FixerPanel} from './panels/FixerPanel';
import {ChopShopPanel} from './panels/ChopShopPanel';
import {DropPanel} from './panels/DropPanel';

export default function App() {
  const {address, isConnected, chainId} = useAccount();
  const {connect, connectors, isPending} = useConnect();
  const {disconnect} = useDisconnect();
  const {switchChain} = useSwitchChain();

  const wrongChain = isConnected && chainId !== robinhoodTestnet.id;

  return (
    <>
      <header className="spread" style={{marginBottom: 16}}>
        <div>
          <h1>AUG//RUN</h1>
          <div className="dim" style={{fontSize: 11}}>
            test harness · Robinhood Chain testnet ({robinhoodTestnet.id})
          </div>
        </div>
        <div className="row">
          {isConnected ? (
            <>
              <span className="mono">{shortAddr(address)}</span>
              <button onClick={() => disconnect()}>disconnect</button>
            </>
          ) : (
            connectors.map((c) => (
              <button key={c.uid} className="primary" disabled={isPending} onClick={() => connect({connector: c})}>
                connect {c.name}
              </button>
            ))
          )}
        </div>
      </header>

      <TxStatusBar />

      {!isConnected && (
        <div className="panel">
          <h2>Not connected</h2>
          <p className="dim">
            Connect your Robinhood wallet to begin. You will be prompted to switch to chain{' '}
            {robinhoodTestnet.id}.
          </p>
          <p className="note">
            This harness holds no keys — every transaction is signed by your own wallet.
          </p>
        </div>
      )}

      {wrongChain && (
        <div className="panel" style={{borderColor: 'var(--warn)'}}>
          <h2 style={{color: 'var(--warn)'}}>Wrong network</h2>
          <p>
            Connected to chain {chainId}. AUG//RUN is deployed on Robinhood Chain testnet (
            {robinhoodTestnet.id}).
          </p>
          <button className="primary" onClick={() => switchChain({chainId: robinhoodTestnet.id})}>
            switch to chain {robinhoodTestnet.id}
          </button>
        </div>
      )}

      {isConnected && !wrongChain && (
        <>
          <div className="grid2">
            <WalletPanel />
            <CyclePanel />
          </div>
          <div className="grid2">
            <MintPanel />
            <ShopPanel />
          </div>
          <BlackMarketPanel />
          <TerminalPanel />
          <FixerPanel />
          <DropPanel />
          <ChopShopPanel />
          <UnitsPanel />
        </>
      )}

      <footer className="note" style={{marginTop: 20, borderTop: '1px solid var(--line)', paddingTop: 10}}>
        <div>
          contracts:{' '}
          {Object.entries(addresses).map(([name, addr]) => (
            <span key={name} style={{marginRight: 12}}>
              <a href={`${EXPLORER}/address/${addr}`} target="_blank" rel="noreferrer">
                {name}
              </a>
            </span>
          ))}
        </div>
      </footer>
    </>
  );
}
