import {VendorShell} from '@/components/VendorShell';
import {FixerClient} from '@/components/vendors/FixerClient';

export const metadata = {
  title: 'The Fixer · AUG//RUN',
  description: 'Borrow $RUN against a Stock//Runner, or $AUG against an unused Augment. Fall to 70% loan-to-value and you are Iced.',
};

export default function Page() {
  return (
    <VendorShell vendor="The Fixer" name="The Fixer" blurb="Borrow $RUN against a Stock//Runner, or $AUG against an unused Augment. Fall to 70% loan-to-value and you are Iced.">
      <FixerClient />
    </VendorShell>
  );
}
