'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { SwapCard } from '@/components/swap/SwapCard';
import { RatesChart } from '@/components/charts/RatesChart';
import { TradeHistory } from '@/components/trades/TradeHistory';
import { TrendingUp } from 'lucide-react';

export default function Home() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 via-white to-gray-100 dark:from-[#0a0a0a] dark:via-[#0f0f0f] dark:to-[#0a0a0a]">
      {/* Header */}
      <header className="border-b border-gray-200 dark:border-[#404040] bg-white/80 dark:bg-[#171717]/80 backdrop-blur-lg sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-600 to-purple-600 flex items-center justify-center">
                <TrendingUp className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className="text-2xl font-bold bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent">
                  Plexus
                </h1>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  Interest Rate Swaps
                </p>
              </div>
            </div>
            <ConnectButton />
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Hero Section */}
        <div className="text-center mb-12">
          <h2 className="text-4xl sm:text-5xl font-bold text-gray-900 dark:text-white mb-4">
            Trade Interest Rates,
            <br />
            <span className="bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent">
              Simply & Securely
            </span>
          </h2>
          <p className="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
            Lock in fixed rates or go variable. Your funds, your choice, grandma-approved simplicity.
          </p>
        </div>

        {/* Main Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Left Column - Swap Card */}
          <div className="lg:col-span-1">
            <SwapCard />
          </div>

          {/* Right Column - Charts & Trades */}
          <div className="lg:col-span-2 space-y-8">
            <RatesChart />
            <TradeHistory />
          </div>
        </div>

        {/* Info Section */}
        <div className="mt-16 grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="p-6 bg-white dark:bg-[#171717] rounded-2xl border border-gray-200 dark:border-[#404040]">
            <div className="w-12 h-12 rounded-xl bg-indigo-100 dark:bg-indigo-950/30 flex items-center justify-center mb-4">
              <span className="text-2xl">🔒</span>
            </div>
            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">
              Secure & Transparent
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              Built on Uniswap V4 with fully audited smart contracts. Your funds stay safe.
            </p>
          </div>

          <div className="p-6 bg-white dark:bg-[#171717] rounded-2xl border border-gray-200 dark:border-[#404040]">
            <div className="w-12 h-12 rounded-xl bg-purple-100 dark:bg-purple-950/30 flex items-center justify-center mb-4">
              <span className="text-2xl">⚡</span>
            </div>
            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">
              Lightning Fast
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              Swap between fixed and variable rates instantly with minimal slippage.
            </p>
          </div>

          <div className="p-6 bg-white dark:bg-[#171717] rounded-2xl border border-gray-200 dark:border-[#404040]">
            <div className="w-12 h-12 rounded-xl bg-green-100 dark:bg-green-950/30 flex items-center justify-center mb-4">
              <span className="text-2xl">📊</span>
            </div>
            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">
              Real-Time Analytics
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              Track rates, monitor trends, and make informed decisions with live data.
            </p>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="mt-20 border-t border-gray-200 dark:border-[#404040] bg-white/80 dark:bg-[#171717]/80 backdrop-blur-lg">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div className="text-center text-sm text-gray-500 dark:text-gray-400">
            <p>© 2024 Plexus. Built with ❤️ on Uniswap V4.</p>
            <p className="mt-2">
              <span className="text-yellow-600">⚠️</span> Demo version with mock data
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
