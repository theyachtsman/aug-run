import {VendorShell} from '@/components/VendorShell';
import {ChopShopClient} from '@/components/vendors/ChopShopClient';

const BLURB =
  'Deposit an item, back it with USDG, and let someone roll for it. The less you back it with, the better everyone’s odds — backing is how you set the difficulty.';

export const metadata = {
  title: 'Chop Shop · AUG//RUN',
  description: BLURB,
};

export default function Page() {
  return (
    <VendorShell vendor="The Scrapper" name="Chop Shop" blurb={BLURB}>
      <ChopShopClient />
    </VendorShell>
  );
}
