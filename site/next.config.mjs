/** @type {import('next').NextConfig} */
export default {
  reactStrictMode: true,

  webpack: (config, {webpack}) => {
    // `wagmi/connectors` is a barrel: importing `injected` from it also drags in the Base Account
    // connector, which reaches the Coinbase CDP SDK and its optional `@x402/*` payment packages.
    // None of that is installed and none of it is reachable at runtime — this site uses the injected
    // connector only. Ignoring the whole namespace beats chasing each missing module one at a time.
    config.plugins.push(
      new webpack.IgnorePlugin({resourceRegExp: /^@x402\//}),
      new webpack.IgnorePlugin({resourceRegExp: /^@coinbase\/cdp-sdk/}),
    );

    // Optional node-only / React Native deps of the same tree, absent by design in a web build.
    config.resolve.fallback = {
      ...config.resolve.fallback,
      'pino-pretty': false,
      encoding: false,
      '@react-native-async-storage/async-storage': false,
    };

    return config;
  },
};
