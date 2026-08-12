import {VendorShell} from '@/components/VendorShell';
import {MarketClient} from '@/components/vendors/MarketClient';

export const metadata = {
  title: 'Black Market · AUG//RUN',
  description: 'Where Stock//Runners change hands. Genesis activates a blank unit for 1,000,000 $RUN; after that it is the floor — take a random unit cheaply, or pay to pick the one you want.',
};

export default function Page() {
  return (
    <VendorShell vendor="The Fence" name="Black Market" blurb="Where Stock//Runners change hands. Genesis activates a blank unit for 1,000,000 $RUN; after that it is the floor — take a random unit cheaply, or pay to pick the one you want.">
      <MarketClient />
    </VendorShell>
  );
}
