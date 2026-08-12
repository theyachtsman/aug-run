import type {Metadata} from 'next';
import './globals.css';
import {Providers} from './providers';
import {Hud} from '@/components/Hud';

export const metadata: Metadata = {
  title: 'AUG//RUN',
  description:
    'A cyberpunk RWA protocol on Robinhood Chain. 333 Stock//Runners, each with its own onchain wallet, chasing real-world yield.',
  openGraph: {
    title: 'AUG//RUN',
    description:
      '333 recovered corporate units. Mint a blank Stock//Runner, augment it, and let it work the market.',
    type: 'website',
  },
  twitter: {card: 'summary_large_image', title: 'AUG//RUN'},
};

export default function RootLayout({children}: {children: React.ReactNode}) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <Hud />
          <div className="shell">{children}</div>
        </Providers>
      </body>
    </html>
  );
}
