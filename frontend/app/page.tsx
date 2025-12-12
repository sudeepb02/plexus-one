'use client';

import dynamic from 'next/dynamic';
import { SwapCard } from '@/components/swap/SwapCard';
import { RatesChart } from '@/components/charts/RatesChart';
import { TradeHistory } from '@/components/trades/TradeHistory';
import { TrendingUp } from 'lucide-react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiProvider } from 'wagmi';
import { SwapProvider } from '@/lib/SwapContext';
import { useState, useMemo } from 'react';
import { darkTheme } from '@rainbow-me/rainbowkit';

// Dynamically import rainbowkit components to avoid pino/thread-stream during build
const RainbowKitProvider = dynamic(
  () => import('@rainbow-me/rainbowkit').then(mod => ({ default: mod.RainbowKitProvider })),
  { ssr: false }
);

const ConnectButton = dynamic(
  () => import('@rainbow-me/rainbowkit').then(mod => ({ default: mod.ConnectButton })),
  { ssr: false }
);

export default function Home() {
  const [queryClient] = useState(() => new QueryClient());
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [wagmiConfig, setWagmiConfig] = useState<any>(null);

  // Load wagmi config on client side only
  useMemo(() => {
    import('@/lib/wagmi').then(mod => {
      setWagmiConfig(mod.config);
    });
  }, []);

  if (!wagmiConfig) {
    return <div className="min-h-screen bg-[#fafbfc] dark:bg-[#0a0d14]" />;
  }

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: '#2563eb',
            accentColorForeground: 'white',
            borderRadius: 'medium',
            fontStack: 'system',
          })}
        >
          <SwapProvider>
            <div className="min-h-screen bg-[#fafbfc] dark:bg-[#0a0d14]">
              {/* Navigation Bar */}
              <nav className="bg-white dark:bg-[#161b22] border-b border-gray-200 dark:border-[#30363d] sticky top-0 z-50">
                <div className="max-w-[1400px] mx-auto px-4 sm:px-6 lg:px-8">
                  <div className="flex justify-between items-center h-16">
                    {/* Logo and Nav Items */}
                    <div className="flex items-center gap-8">
                      <div className="flex items-center gap-2">
                        <div className="w-8 h-8 rounded bg-blue-600 flex items-center justify-center">
                          <TrendingUp className="w-5 h-5 text-white" />
                        </div>
                        <span className="text-lg font-semibold text-gray-900 dark:text-white">
                          PlexusOne
                        </span>
                      </div>
                      
                      <div className="hidden md:flex items-center gap-6">
                        <a href="#" className="text-sm font-medium text-gray-900 dark:text-white hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                          Swap
                        </a>
                        <a href="#" className="text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                          Markets
                        </a>
                        <a href="#" className="text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                          Portfolio
                        </a>
                      </div>
                    </div>

                    {/* Wallet Connect - Custom Styled */}
                    <div className="rainbowkit-custom">
                      <ConnectButton 
                        showBalance={false}
                        chainStatus="icon"
                        accountStatus="avatar"
                      />
                    </div>
                  </div>
                </div>
              </nav>

              {/* Main Content */}
              <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
                {/* Main Grid - Optimized for alignment */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                  {/* Left Column - Chart (takes 2 columns) */}
                  <div className="lg:col-span-2 space-y-6">
                    <RatesChart />
                    <TradeHistory />
                  </div>

                  {/* Right Column - Swap Card (takes 1 column, sticky on larger screens) */}
                  <div className="lg:col-span-1">
                    <div className="lg:sticky lg:top-6">
                      <SwapCard />
                    </div>
                  </div>
                </div>
              </main>

              {/* Footer */}
              <footer className="mt-16 border-t border-gray-200 dark:border-[#30363d] bg-white dark:bg-[#161b22]">
                <div className="max-w-[1400px] mx-auto px-4 sm:px-6 lg:px-8 py-8">
                  <div className="flex flex-col md:flex-row justify-between items-center gap-4">
                    <div className="text-sm text-gray-600 dark:text-gray-400">
                      © 2024 PlexusOne. Built on Uniswap V4.
                    </div>
                    <div className="flex items-center gap-6 text-sm text-gray-600 dark:text-gray-400">
                      <a href="#" className="hover:text-blue-600 dark:hover:text-blue-400 transition-colors">Docs</a>
                      <a href="#" className="hover:text-blue-600 dark:hover:text-blue-400 transition-colors">GitHub</a>
                      <a href="#" className="hover:text-blue-600 dark:hover:text-blue-400 transition-colors">Discord</a>
                    </div>
                  </div>
                </div>
              </footer>
            </div>
          </SwapProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
