import {VendorShell} from '@/components/VendorShell';
import {DropClient} from '@/components/vendors/DropClient';

export const metadata = {
  title: 'The Drop · AUG//RUN',
  description: 'Protocol revenue becomes real-world assets in Stock//Runner wallets. Weekly, anchored to Monday 00:00 UTC. Delivery is pull-based.',
};

export default function Page() {
  return (
    <VendorShell vendor="The Courier" name="The Drop" blurb="Protocol revenue becomes real-world assets in Stock//Runner wallets. Weekly, anchored to Monday 00:00 UTC. Delivery is pull-based.">
      <DropClient />
    </VendorShell>
  );
}
