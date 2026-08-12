import {VendorShell} from '@/components/VendorShell';
import {TerminalClient} from '@/components/vendors/TerminalClient';

export const metadata = {
  title: 'The Terminal · AUG//RUN',
  description: 'Stake $AUG for a cut of protocol revenue, or provide liquidity for the same. No vendor, no negotiation — staking is not a transaction with anyone, so it gets a machine.',
};

export default function Page() {
  return (
    <VendorShell vendor="Unstaffed" name="The Terminal" blurb="Stake $AUG for a cut of protocol revenue, or provide liquidity for the same. No vendor, no negotiation — staking is not a transaction with anyone, so it gets a machine.">
      <TerminalClient />
    </VendorShell>
  );
}
