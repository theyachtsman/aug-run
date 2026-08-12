import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // Bound to 0.0.0.0 so the harness is reachable from any browser on the LAN,
    // not just localhost. It holds no keys — every transaction is signed by the
    // visitor's own wallet — but it is on every interface, so treat it as visible
    // to anyone on your network.
    host: '0.0.0.0',
    port: 3333,
    strictPort: true,
  },
  preview: {
    host: '0.0.0.0',
    port: 3333,
    strictPort: true,
  },
});
