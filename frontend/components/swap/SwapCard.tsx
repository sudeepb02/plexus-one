'use client';

import { useState, useEffect } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, TrendingUp, TrendingDown, Info } from 'lucide-react';

export function SwapCard() {
  const { swapMode, setSwapMode, inputAmount, setInputAmount, isLoading } = useSwap();
  const [estimatedOutput, setEstimatedOutput] = useState('0.00');
  const [showScenarios, setShowScenarios] = useState(false);

  // Mock implied rate - in production, fetch from contract
  const impliedRate = 5.25;
  
  // Position type: 'long' = betting rates go up, 'short' = betting rates go down
  const isLongPosition = swapMode === 'fixed';

  const handleSwap = async () => {
    console.log('Executing swap:', { 
      position: isLongPosition ? 'Long' : 'Short',
      inputAmount,
      impliedRate 
    });
    // TODO: Implement actual swap logic with smart contracts
  };

  const handleInputChange = (value: string) => {
    setInputAmount(value);
    // Mock calculation - replace with actual calculation from smart contract
    const estimated = value ? (parseFloat(value) * 20).toFixed(2) : '0.00';
    setEstimatedOutput(estimated);
    
    // Show scenarios when user enters amount
    setShowScenarios(value !== '' && parseFloat(value) > 0);
  };

  // Calculate profit/loss scenarios
  const calculateScenarios = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) {
      return { bullish: { rate: 7, pnl: 0 }, bearish: { rate: 3, pnl: 0 } };
    }

    const amount = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);

    if (isLongPosition) {
      // Long: Profit if actual yield > implied rate
      const bullishPnl = ytAmount * (0.07 - impliedRate / 100) - amount; // At 7% yield
      const bearishPnl = ytAmount * (0.03 - impliedRate / 100) - amount; // At 3% yield
      return {
        bullish: { rate: 7, pnl: bullishPnl },
        bearish: { rate: 3, pnl: bearishPnl }
      };
    } else {
      // Short: Profit if actual yield < implied rate
      const premium = amount * (impliedRate / 100);
      const bullishPnl = premium - (ytAmount * 0.07); // At 7% yield (loss)
      const bearishPnl = premium - (ytAmount * 0.03); // At 3% yield (profit)
      return {
        bullish: { rate: 7, pnl: bullishPnl },
        bearish: { rate: 3, pnl: bearishPnl }
      };
    }
  };

  const scenarios = calculateScenarios();

  return (
    <div className="w-full bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      {/* Header */}
      <div className="border-b border-gray-200 dark:border-[#30363d] p-4">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Interest Rate Swap</h2>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
          Take a position on future yield rates
        </p>
      </div>

      <div className="p-4 space-y-4">
        {/* Position Selector - Long vs Short */}
        <div>
          <label className="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 block">
            Position Type
          </label>
          <div className="flex gap-2 p-1 bg-gray-100 dark:bg-[#0d1117] rounded-lg">
            <button
              onClick={() => setSwapMode('fixed')}
              className={`flex-1 py-2.5 px-4 rounded text-sm font-medium transition-all flex items-center justify-center gap-2 ${
                isLongPosition
                  ? 'bg-white dark:bg-[#161b22] text-green-600 dark:text-green-400 shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
              }`}
            >
              <TrendingUp className="w-4 h-4" />
              Long Rates
            </button>
            <button
              onClick={() => setSwapMode('variable')}
              className={`flex-1 py-2.5 px-4 rounded text-sm font-medium transition-all flex items-center justify-center gap-2 ${
                !isLongPosition
                  ? 'bg-white dark:bg-[#161b22] text-red-600 dark:text-red-400 shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
              }`}
            >
              <TrendingDown className="w-4 h-4" />
              Short Rates
            </button>
          </div>
        </div>

        {/* Implied Rate Display */}
        <div className="p-3 bg-blue-50 dark:bg-blue-950/20 rounded-lg border border-blue-200 dark:border-blue-900/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
                Current Implied Rate
              </span>
              <button 
                className="text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300"
                title="The market's expected yield. You profit if actual rates differ from this."
              >
                <Info className="w-3.5 h-3.5" />
              </button>
            </div>
            <span className="text-lg font-bold text-blue-600 dark:text-blue-400">
              {impliedRate}%
            </span>
          </div>
          <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">
            Your breakeven point
          </p>
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
              {isLongPosition ? 'Buying YT' : 'Selling YT'}
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
                  YT
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Directional Information */}
        {!showScenarios && (
          <div className={`p-3 rounded-lg border ${
            isLongPosition 
              ? 'bg-green-50 dark:bg-green-950/20 border-green-200 dark:border-green-900/50'
              : 'bg-red-50 dark:bg-red-950/20 border-red-200 dark:border-red-900/50'
          }`}>
            <div className="flex items-start gap-2">
              <Info className={`w-4 h-4 mt-0.5 flex-shrink-0 ${
                isLongPosition 
                  ? 'text-green-600 dark:text-green-400'
                  : 'text-red-600 dark:text-red-400'
              }`} />
              <div className="flex-1">
                <p className="text-xs font-medium text-gray-900 dark:text-white mb-1">
                  {isLongPosition ? "You're betting rates will INCREASE" : "You're betting rates will DECREASE"}
                </p>
                <p className="text-xs text-gray-600 dark:text-gray-400">
                  {isLongPosition 
                    ? `Profit if actual yield rises above ${impliedRate}%`
                    : `Profit if actual yield drops below ${impliedRate}%`
                  }
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Profit/Loss Scenarios - Shown when user enters amount */}
        {showScenarios && (
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
                Expected Outcomes
              </span>
            </div>
            
            {/* Bullish Scenario */}
            <div className="p-2.5 rounded-lg bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d]">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <TrendingUp className="w-3.5 h-3.5 text-green-600 dark:text-green-400" />
                  <span className="text-xs text-gray-600 dark:text-gray-400">
                    If rates reach {scenarios.bullish.rate}%
                  </span>
                </div>
                <span className={`text-xs font-semibold ${
                  scenarios.bullish.pnl >= 0
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-red-600 dark:text-red-400'
                }`}>
                  {scenarios.bullish.pnl >= 0 ? '+' : ''}{scenarios.bullish.pnl.toFixed(2)} USDC
                </span>
              </div>
            </div>

            {/* Bearish Scenario */}
            <div className="p-2.5 rounded-lg bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d]">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <TrendingDown className="w-3.5 h-3.5 text-red-600 dark:text-red-400" />
                  <span className="text-xs text-gray-600 dark:text-gray-400">
                    If rates drop to {scenarios.bearish.rate}%
                  </span>
                </div>
                <span className={`text-xs font-semibold ${
                  scenarios.bearish.pnl >= 0
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-red-600 dark:text-red-400'
                }`}>
                  {scenarios.bearish.pnl >= 0 ? '+' : ''}{scenarios.bearish.pnl.toFixed(2)} USDC
                </span>
              </div>
            </div>
          </div>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!inputAmount || isLoading}
          className={`w-full py-3 rounded-lg font-medium text-sm transition-all ${
            !inputAmount || isLoading
              ? 'bg-gray-100 dark:bg-[#0d1117] text-gray-400 dark:text-gray-600 cursor-not-allowed border border-gray-200 dark:border-[#30363d]'
              : isLongPosition
              ? 'bg-green-600 hover:bg-green-700 text-white shadow-sm'
              : 'bg-red-600 hover:bg-red-700 text-white shadow-sm'
          }`}
        >
          {isLoading ? 'Processing...' : !inputAmount ? 'Enter amount' : `${isLongPosition ? 'Long' : 'Short'} ${impliedRate}%`}
        </button>
      </div>
    </div>
  );
}
