import {VendorShell} from '@/components/VendorShell';
import {RipperdocClient} from '@/components/vendors/RipperdocClient';

export const metadata = {
  title: 'Ripperdoc · AUG//RUN',
  description: 'Augments and Expansion Modules. Half of every payment burns permanently. Once seated, an Augment is bound to that unit — which is what makes tenure mean anything.',
};

export default function Page() {
  return (
    <VendorShell vendor="The Ripperdoc" name="Ripperdoc" blurb="Augments and Expansion Modules. Half of every payment burns permanently. Once seated, an Augment is bound to that unit — which is what makes tenure mean anything.">
      <RipperdocClient />
    </VendorShell>
  );
}
