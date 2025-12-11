'use client';

import { useState } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, Zap, TrendingUp } from 'lucide-react';

export function SwapCard() {
  const { swapMode, setSwapMode, inputAmount, setInputAmount, isLoading } = useSwap();
  const [estimatedOutput, setEstimatedOutput] = useState('0.00');

  const handleSwap = async () => {
    console.log('Swapping:', { swapMode, inputAmount });
    // TODO: Implement actual swap logic with smart contracts
  };

  const handleInputChange = (value: string) => {
    setInputAmount(value);
    // Mock calculation - replace with actual calculation from smart contract
    const estimated = value ? (parseFloat(value) * 0.95).toFixed(2) : '0.00';
    setEstimatedOutput(estimated);
  };

  const currentRate = swapMode === 'fixed' ? '5.25%' : '4.80%';

  return (
    <div className="w-full max-w-lg bg-white dark:bg-[#171717] rounded-3xl shadow-2xl p-6 border border-gray-200 dark:border-[#404040]">
      {/* Mode Selector */}
      <div className="flex gap-3 mb-6">
        <button
          onClick={() => setSwapMode('fixed')}
          className={`flex-1 py-3 px-4 rounded-2xl font-semibold transition-all duration-200 flex items-center justify-center gap-2 ${
            swapMode === 'fixed'
              ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/50'
              : 'bg-gray-100 dark:bg-[#262626] text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-[#2a2a2a]'
          }`}
        >
          <Zap className="w-4 h-4" />
          Get Fixed Rate
        </button>
        <button
          onClick={() => setSwapMode('variable')}
          className={`flex-1 py-3 px-4 rounded-2xl font-semibold transition-all duration-200 flex items-center justify-center gap-2 ${
            swapMode === 'variable'
              ? 'bg-purple-600 text-white shadow-lg shadow-purple-500/50'
              : 'bg-gray-100 dark:bg-[#262626] text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-[#2a2a2a]'
          }`}
        >
          <TrendingUp className="w-4 h-4" />
          Get Variable Rate
        </button>
      </div>

      {/* Input Section */}
      <div className="mb-4">
        <div className="flex justify-between mb-2">
          <span className="text-sm text-gray-500 dark:text-gray-400">You pay</span>
          <span className="text-sm text-gray-500 dark:text-gray-400">Balance: 0.00</span>
        </div>
        <div className="bg-gray-50 dark:bg-[#262626] rounded-2xl p-4 border border-gray-200 dark:border-[#404040]">
          <div className="flex items-center justify-between">
            <input
              type="number"
              value={inputAmount}
              onChange={(e) => handleInputChange(e.target.value)}
              placeholder="0.00"
              className="bg-transparent text-3xl font-semibold outline-none w-full text-gray-900 dark:text-white"
            />
            <div className="flex items-center gap-2 bg-white dark:bg-[#171717] px-4 py-2 rounded-xl border border-gray-200 dark:border-[#404040]">
              <div className="w-6 h-6 rounded-full bg-blue-500" />
              <span className="font-semibold text-gray-900 dark:text-white">USDC</span>
            </div>
          </div>
        </div>
      </div>

      {/* Swap Arrow */}
      <div className="flex justify-center -my-2 relative z-10">
        <button className="bg-gray-100 dark:bg-[#262626] p-3 rounded-xl border-4 border-white dark:border-[#171717] hover:bg-gray-200 dark:hover:bg-[#2a2a2a] transition-colors">
          <ArrowDownUp className="w-5 h-5 text-gray-600 dark:text-gray-400" />
        </button>
      </div>

      {/* Output Section */}
      <div className="mb-6">
        <div className="flex justify-between mb-2">
          <span className="text-sm text-gray-500 dark:text-gray-400">You receive</span>
          <span className="text-sm text-gray-500 dark:text-gray-400">
            Rate: {currentRate}
          </span>
        </div>
        <div className="bg-gray-50 dark:bg-[#262626] rounded-2xl p-4 border border-gray-200 dark:border-[#404040]">
          <div className="flex items-center justify-between">
            <div className="text-3xl font-semibold text-gray-900 dark:text-white">
              {estimatedOutput}
            </div>
            <div className="flex items-center gap-2 bg-white dark:bg-[#171717] px-4 py-2 rounded-xl border border-gray-200 dark:border-[#404040]">
              <div className="w-6 h-6 rounded-full bg-gradient-to-br from-indigo-500 to-purple-500" />
              <span className="font-semibold text-gray-900 dark:text-white">
                {swapMode === 'fixed' ? 'ytUSDC' : 'USDC'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Info Box */}
      <div className="mb-6 p-4 bg-gradient-to-r from-indigo-50 to-purple-50 dark:from-indigo-950/30 dark:to-purple-950/30 rounded-2xl border border-indigo-200 dark:border-indigo-900">
        <div className="flex justify-between text-sm mb-2">
          <span className="text-gray-600 dark:text-gray-400">Implied Rate</span>
          <span className="font-semibold text-gray-900 dark:text-white">{currentRate}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-600 dark:text-gray-400">Price Impact</span>
          <span className="font-semibold text-green-600 dark:text-green-400">&lt; 0.5%</span>
        </div>
      </div>

      {/* Swap Button */}
      <button
        onClick={handleSwap}
        disabled={!inputAmount || isLoading}
        className={`w-full py-4 rounded-2xl font-bold text-lg transition-all duration-200 ${
          !inputAmount || isLoading
            ? 'bg-gray-200 dark:bg-[#262626] text-gray-400 dark:text-gray-600 cursor-not-allowed'
            : swapMode === 'fixed'
            ? 'bg-gradient-to-r from-indigo-600 to-indigo-700 hover:from-indigo-700 hover:to-indigo-800 text-white shadow-lg shadow-indigo-500/50'
            : 'bg-gradient-to-r from-purple-600 to-purple-700 hover:from-purple-700 hover:to-purple-800 text-white shadow-lg shadow-purple-500/50'
        }`}
      >
        {isLoading ? 'Swapping...' : !inputAmount ? 'Enter amount' : 'Swap'}
      </button>
    </div>
  );
}
