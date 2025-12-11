'use client';

import { useState } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, Info } from 'lucide-react';

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
    <div className="w-full bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      {/* Header */}
      <div className="border-b border-gray-200 dark:border-[#30363d] p-4">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Swap</h2>
      </div>

      <div className="p-4 space-y-4">
        {/* Mode Selector */}
        <div className="flex gap-2 p-1 bg-gray-100 dark:bg-[#0d1117] rounded-lg">
          <button
            onClick={() => setSwapMode('fixed')}
            className={`flex-1 py-2 px-4 rounded text-sm font-medium transition-all ${
              swapMode === 'fixed'
                ? 'bg-white dark:bg-[#161b22] text-gray-900 dark:text-white shadow-sm'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            Fixed Rate
          </button>
          <button
            onClick={() => setSwapMode('variable')}
            className={`flex-1 py-2 px-4 rounded text-sm font-medium transition-all ${
              swapMode === 'variable'
                ? 'bg-white dark:bg-[#161b22] text-gray-900 dark:text-white shadow-sm'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            Variable Rate
          </button>
        </div>

        {/* Input Section */}
        <div>
          <div className="flex justify-between mb-2">
            <span className="text-xs font-medium text-gray-600 dark:text-gray-400">You pay</span>
            <span className="text-xs text-gray-500 dark:text-gray-500">Balance: 0.00</span>
          </div>
          <div className="bg-gray-50 dark:bg-[#0d1117] rounded-lg p-3 border border-gray-200 dark:border-[#30363d]">
            <div className="flex items-center justify-between gap-3">
              <input
                type="number"
                value={inputAmount}
                onChange={(e) => handleInputChange(e.target.value)}
                placeholder="0.00"
                className="bg-transparent text-2xl font-semibold outline-none w-full text-gray-900 dark:text-white"
              />
              <div className="flex items-center gap-2 bg-white dark:bg-[#161b22] px-3 py-2 rounded border border-gray-200 dark:border-[#30363d] whitespace-nowrap">
                <div className="w-5 h-5 rounded-full bg-blue-600" />
                <span className="font-medium text-gray-900 dark:text-white text-sm">USDC</span>
              </div>
            </div>
          </div>
        </div>

        {/* Swap Arrow */}
        <div className="flex justify-center">
          <button className="bg-gray-100 dark:bg-[#0d1117] p-2 rounded border border-gray-200 dark:border-[#30363d] hover:bg-gray-200 dark:hover:bg-[#1f2937] transition-colors">
            <ArrowDownUp className="w-4 h-4 text-gray-600 dark:text-gray-400" />
          </button>
        </div>

        {/* Output Section */}
        <div>
          <div className="flex justify-between mb-2">
            <span className="text-xs font-medium text-gray-600 dark:text-gray-400">You receive</span>
            <span className="text-xs text-gray-500 dark:text-gray-500">
              Rate: {currentRate}
            </span>
          </div>
          <div className="bg-gray-50 dark:bg-[#0d1117] rounded-lg p-3 border border-gray-200 dark:border-[#30363d]">
            <div className="flex items-center justify-between gap-3">
              <div className="text-2xl font-semibold text-gray-900 dark:text-white">
                {estimatedOutput}
              </div>
              <div className="flex items-center gap-2 bg-white dark:bg-[#161b22] px-3 py-2 rounded border border-gray-200 dark:border-[#30363d] whitespace-nowrap">
                <div className="w-5 h-5 rounded-full bg-gradient-to-br from-blue-500 to-purple-500" />
                <span className="font-medium text-gray-900 dark:text-white text-sm">
                  {swapMode === 'fixed' ? 'ytUSDC' : 'USDC'}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Info Box */}
        <div className="p-3 bg-blue-50 dark:bg-blue-950/20 rounded-lg border border-blue-200 dark:border-blue-900/50">
          <div className="flex items-start gap-2 mb-2">
            <Info className="w-4 h-4 text-blue-600 dark:text-blue-400 mt-0.5 flex-shrink-0" />
            <div className="flex-1">
              <div className="flex justify-between text-xs mb-1">
                <span className="text-gray-600 dark:text-gray-400">Implied Rate</span>
                <span className="font-medium text-gray-900 dark:text-white">{currentRate}</span>
              </div>
              <div className="flex justify-between text-xs">
                <span className="text-gray-600 dark:text-gray-400">Price Impact</span>
                <span className="font-medium text-green-600 dark:text-green-400">&lt; 0.5%</span>
              </div>
            </div>
          </div>
        </div>

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!inputAmount || isLoading}
          className={`w-full py-3 rounded-lg font-medium text-sm transition-all ${
            !inputAmount || isLoading
              ? 'bg-gray-100 dark:bg-[#0d1117] text-gray-400 dark:text-gray-600 cursor-not-allowed border border-gray-200 dark:border-[#30363d]'
              : 'bg-blue-600 hover:bg-blue-700 text-white shadow-sm'
          }`}
        >
          {isLoading ? 'Swapping...' : !inputAmount ? 'Enter amount' : 'Swap'}
        </button>
      </div>
    </div>
  );
}
