'use client';

import { useState } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, TrendingUp, TrendingDown, Info, ChevronDown, ChevronUp, AlertTriangle, Clock, Calculator, Zap } from 'lucide-react';

export function SwapCard() {
  const { swapMode, setSwapMode, inputAmount, setInputAmount, isLoading } = useSwap();
  const [estimatedOutput, setEstimatedOutput] = useState('0.00');
  const [showScenarios, setShowScenarios] = useState(false);
  const [advancedMode, setAdvancedMode] = useState(false);
  const [showTooltip, setShowTooltip] = useState<string | null>(null);
  const [simulatedRate, setSimulatedRate] = useState(5.25);

  // Mock implied rate - in production, fetch from contract
  const impliedRate = 5.25;
  
  // Mock maturity date - in production, fetch from contract
  const maturityDate = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);
  const daysToMaturity = Math.floor((maturityDate.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
  
  // Position type: 'long' = betting rates go up, 'short' = betting rates go down
  const isLongPosition = swapMode === 'fixed';

  const handleSwap = async () => {
    // Swap logic here
    console.log('Swapping:', { swapMode, inputAmount, estimatedOutput });
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setInputAmount(value);
    
    // Mock calculation
    if (swapMode === 'fixed') {
      setEstimatedOutput((parseFloat(value) * 20 || 0).toFixed(2));
    } else {
      setEstimatedOutput((parseFloat(value) * 0.048 || 0).toFixed(2));
    }
    
    setShowScenarios(parseFloat(value) > 0);
  };

  // Calculate P&L at a specific rate (for simulator)
  const calculatePnLAtRate = (rate: number) => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return 0;
    const amount = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);

    if (isLongPosition) {
      return ytAmount * (rate / 100 - impliedRate / 100);
    } else {
      const premium = amount * (impliedRate / 100);
      return premium - (ytAmount * (rate / 100));
    }
  };

  // Calculate breakeven rate
  const calculateBreakeven = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return impliedRate;
    const amount = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);
    
    if (isLongPosition) {
      return ((amount / ytAmount) + (impliedRate / 100)) * 100;
    } else {
      const premium = amount * (impliedRate / 100);
      return (premium / ytAmount) * 100;
    }
  };

  const breakeven = calculateBreakeven();
  const simulatedPnL = calculatePnLAtRate(simulatedRate);

  // Tooltip Component
  const Tooltip = ({ id, title, description }: { id: string; title: string; description: string }) => (
    <div className="relative inline-block">
      <button
        onMouseEnter={() => setShowTooltip(id)}
        onMouseLeave={() => setShowTooltip(null)}
        className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
      >
        <Info className="w-3 h-3" />
      </button>
      {showTooltip === id && (
        <div className="absolute left-0 top-5 z-50 w-56 p-2 bg-gray-900 dark:bg-gray-800 text-white text-xs rounded shadow-lg">
          <div className="font-semibold mb-1">{title}</div>
          <div className="text-gray-300">{description}</div>
        </div>
      )}
    </div>
  );

  return (
    <div className="w-full bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      {/* Compact Header with Maturity & Implied Rate */}
      <div className="p-3 border-b border-gray-200 dark:border-[#30363d]">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-base font-semibold text-gray-900 dark:text-white">Interest Rate Swap</h2>
          <button
            onClick={() => setAdvancedMode(!advancedMode)}
            className="flex items-center gap-1 px-2 py-1 text-xs font-medium text-blue-600 dark:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-950/30 rounded transition-colors"
          >
            <Zap className="w-3 h-3" />
            {advancedMode ? 'Simple' : 'Advanced'}
          </button>
        </div>
        
        {/* Compact Info Row */}
        <div className="flex items-center justify-between text-xs">
          <div className="flex items-center gap-1.5">
            <Clock className="w-3.5 h-3.5 text-gray-400" />
            <span className="text-gray-600 dark:text-gray-400">Maturity:</span>
            <span className="font-medium text-gray-900 dark:text-white">{daysToMaturity}d</span>
          </div>
          <div className="flex items-center gap-1">
            <span className="text-gray-600 dark:text-gray-400">Implied Rate:</span>
            <span className="text-base font-bold text-blue-600 dark:text-blue-400">{impliedRate}%</span>
            <Tooltip
              id="implied-rate"
              title="Implied Rate"
              description="The market's expected yield rate based on current prices."
            />
          </div>
        </div>
      </div>

      <div className="p-4 space-y-3">
        {/* Position Selector */}
        <div className="grid grid-cols-2 gap-2 p-1 bg-gray-100 dark:bg-[#0d1117] rounded-lg">
          <button
            onClick={() => setSwapMode('fixed')}
            className={`flex items-center justify-center gap-1.5 py-2 px-3 rounded-md text-xs font-medium transition-all ${
              swapMode === 'fixed'
                ? 'bg-white dark:bg-[#161b22] text-green-600 dark:text-green-400 shadow-sm'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            <TrendingUp className="w-3.5 h-3.5" />
            Long Rates
          </button>
          <button
            onClick={() => setSwapMode('variable')}
            className={`flex items-center justify-center gap-1.5 py-2 px-3 rounded-md text-xs font-medium transition-all ${
              swapMode === 'variable'
                ? 'bg-white dark:bg-[#161b22] text-red-600 dark:text-red-400 shadow-sm'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            <TrendingDown className="w-3.5 h-3.5" />
            Short Rates
          </button>
        </div>

        {/* Input Section */}
        <div className="space-y-2">
          <div className="flex items-center justify-between text-xs">
            <span className="text-gray-600 dark:text-gray-400">You pay</span>
            <span className="text-gray-500 dark:text-gray-400">Balance: 0.00</span>
          </div>
          <div className="relative">
            <input
              type="number"
              value={inputAmount}
              onChange={handleInputChange}
              placeholder="0.00"
              className="w-full px-3 py-2.5 pr-16 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400"
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
              <div className="w-5 h-5 rounded-full bg-blue-600"></div>
              <span className="text-sm font-medium text-gray-900 dark:text-white">USDC</span>
            </div>
          </div>
        </div>

        {/* Swap Direction Icon */}
        <div className="flex justify-center">
          <div className="p-1.5 bg-gray-100 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d]">
            <ArrowDownUp className="w-4 h-4 text-gray-600 dark:text-gray-400" />
          </div>
        </div>

        {/* Output Section */}
        <div className="space-y-2">
          <div className="flex items-center justify-between text-xs">
            <span className="text-gray-600 dark:text-gray-400">You receive</span>
            <span className="text-gray-500 dark:text-gray-400">Buying YT</span>
          </div>
          <div className="relative">
            <input
              type="text"
              value={estimatedOutput}
              readOnly
              placeholder="0.00"
              className="w-full px-3 py-2.5 pr-14 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white"
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
              <div className="w-5 h-5 rounded-full bg-purple-600"></div>
              <span className="text-sm font-medium text-gray-900 dark:text-white">YT</span>
            </div>
          </div>
        </div>

        {/* Breakeven Display - Compact */}
        {showScenarios && (
          <div className="flex items-center justify-between p-2 bg-purple-50 dark:bg-purple-950/20 rounded-lg border border-purple-200 dark:border-purple-900/50">
            <div className="flex items-center gap-1.5">
              <Calculator className="w-3.5 h-3.5 text-purple-600 dark:text-purple-400" />
              <span className="text-xs font-medium text-gray-900 dark:text-white">Breakeven</span>
              <Tooltip
                id="breakeven"
                title="Breakeven Rate"
                description="The yield rate where you neither profit nor lose."
              />
            </div>
            <span className="text-sm font-bold text-purple-600 dark:text-purple-400">
              {breakeven.toFixed(2)}%
            </span>
          </div>
        )}

        {/* Collateral Warning */}
        {swapMode === 'variable' && parseFloat(inputAmount) > 0 && (
          <div className="flex items-start gap-2 p-2 bg-amber-50 dark:bg-amber-950/20 rounded-lg border border-amber-200 dark:border-amber-900/50">
            <AlertTriangle className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
            <div className="text-xs text-amber-900 dark:text-amber-200">
              <span className="font-medium">Collateral Required:</span> {(parseFloat(inputAmount) * 0.1).toFixed(2)} USDC
            </div>
          </div>
        )}

        {/* Advanced Mode: Interactive P&L Simulator */}
        {advancedMode && showScenarios && (
          <div className="p-3 bg-gray-50 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d] space-y-2.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-gray-600 dark:text-gray-400">P&L Simulator</span>
              <span className="text-xs text-gray-500 dark:text-gray-500">Drag to test</span>
            </div>
            
            {/* Rate Slider */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs">
                <span className="text-gray-600 dark:text-gray-400">Yield Rate</span>
                <span className="font-semibold text-gray-900 dark:text-white">{simulatedRate.toFixed(2)}%</span>
              </div>
              <input
                type="range"
                min="0"
                max="15"
                step="0.25"
                value={simulatedRate}
                onChange={(e) => setSimulatedRate(parseFloat(e.target.value))}
                className="w-full h-1.5 bg-gray-200 dark:bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-600"
              />
              <div className="flex justify-between text-xs text-gray-500 dark:text-gray-400">
                <span>0%</span>
                <span>15%</span>
              </div>
            </div>

            {/* P&L Result - Compact */}
            <div className={`p-2 rounded-lg ${
              simulatedPnL >= 0 
                ? 'bg-green-50 dark:bg-green-950/20 border border-green-200 dark:border-green-900/50'
                : 'bg-red-50 dark:bg-red-950/20 border border-red-200 dark:border-red-900/50'
            }`}>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600 dark:text-gray-400">
                  P&L at {simulatedRate.toFixed(2)}%
                </span>
                <span className={`text-sm font-bold ${
                  simulatedPnL >= 0
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-red-600 dark:text-red-400'
                }`}>
                  {simulatedPnL >= 0 ? '+' : ''}{simulatedPnL.toFixed(2)} USDC
                </span>
              </div>
            </div>

            {/* Visual Gradient Bar - Compact */}
            <div className="space-y-1.5">
              <div className="relative h-6 bg-gradient-to-r from-red-500 via-gray-300 to-green-500 rounded overflow-hidden">
                {/* Implied Rate Marker */}
                <div 
                  className="absolute top-0 bottom-0 w-0.5 bg-gray-900 dark:bg-white z-10"
                  style={{ left: `${(impliedRate / 15) * 100}%` }}
                >
                  <div className="absolute -top-4 left-1/2 -translate-x-1/2 text-xs font-bold text-gray-900 dark:text-white whitespace-nowrap">
                    {impliedRate}%
                  </div>
                </div>
                {/* Simulated Rate Marker */}
                <div 
                  className="absolute top-0 bottom-0 w-1 bg-blue-600 z-20"
                  style={{ left: `${(simulatedRate / 15) * 100}%` }}
                />
              </div>
              <div className="flex justify-between text-xs text-gray-500 dark:text-gray-400">
                <span>{isLongPosition ? 'Loss' : 'Profit'}</span>
                <span>{isLongPosition ? 'Profit' : 'Loss'}</span>
              </div>
            </div>
          </div>
        )}

        {/* Simple Scenarios - Collapsible */}
        {!advancedMode && showScenarios && (
          <button
            onClick={() => setShowScenarios(!showScenarios)}
            className="w-full flex items-center justify-between p-2 text-xs font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-[#0d1117] rounded-lg transition-colors"
          >
            <span>Quick Scenarios</span>
            <ChevronDown className="w-4 h-4" />
          </button>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!inputAmount || parseFloat(inputAmount) === 0 || isLoading}
          className="w-full py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 dark:disabled:bg-gray-700 text-white font-medium rounded-lg transition-colors disabled:cursor-not-allowed text-sm"
        >
          {isLoading ? 'Processing...' : parseFloat(inputAmount) === 0 ? 'Enter amount' : 'Execute Swap'}
        </button>
      </div>
    </div>
  );
}
