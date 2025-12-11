'use client';

import { useState } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, TrendingUp, TrendingDown, Info, ChevronDown, ChevronUp, AlertTriangle, Clock, Calculator, Zap, DollarSign } from 'lucide-react';

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
  const yearsToMaturity = daysToMaturity / 365;
  
  // Position type: 'long' = betting rates go up, 'short' = betting rates go down
  const isLongPosition = swapMode === 'fixed';

  const handleSwap = async () => {
    // Swap logic here
    console.log('Swapping:', { swapMode, inputAmount, estimatedOutput });
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setInputAmount(value);
    
    // Fixed: Calculate output based on time-adjusted implied rate
    // YT value = Principal * Rate * Time
    const principal = parseFloat(value) || 0;
    
    if (swapMode === 'fixed') {
      // Buying YT (Long): How many YT tokens do we get for our USDC?
      // YT Price = Rate * Time (e.g., 5.25% * 0.5 years = 2.625% of principal)
      const ytPrice = (impliedRate / 100) * yearsToMaturity;
      const ytAmount = principal / ytPrice;
      setEstimatedOutput(ytAmount.toFixed(2));
    } else {
      // Selling YT (Short): How much USDC do we get for selling YT?
      // With 10x leverage: can sell 10x worth of YT
      const ytPrice = (impliedRate / 100) * yearsToMaturity;
      const ytAmount = (principal * 10) / ytPrice;
      setEstimatedOutput(ytAmount.toFixed(2));
    }
    
    setShowScenarios(parseFloat(value) > 0);
  };

  // Fixed: Calculate P&L at a specific rate (time-adjusted)
  const calculatePnLAtRate = (rate: number) => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return 0;
    const amountIn = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);

    if (isLongPosition) {
      // Long Position: Bought YT, profit when actual yield > implied
      // Cost: amountIn USDC
      // Payout at maturity: ytAmount * (actualRate / 100) * yearsToMaturity
      const payout = ytAmount * (rate / 100) * yearsToMaturity;
      return payout - amountIn;
    } else {
      // Short Position: Sold YT, profit when actual yield < implied
      // Premium received: YT sold at implied rate
      const premiumReceived = ytAmount * (impliedRate / 100) * yearsToMaturity;
      // Debt at maturity: ytAmount * (actualRate / 100) * yearsToMaturity
      const debt = ytAmount * (rate / 100) * yearsToMaturity;
      return premiumReceived - debt;
    }
  };

  // Fixed: Calculate breakeven rate (time-adjusted)
  const calculateBreakeven = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return impliedRate;
    const amountIn = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);
    
    if (ytAmount === 0 || yearsToMaturity === 0) return impliedRate;
    
    // Breakeven is where P&L = 0
    // For long: payout = cost => ytAmount * (rate/100) * time = amountIn
    // rate = (amountIn / (ytAmount * time)) * 100
    return (amountIn / (ytAmount * yearsToMaturity)) * 100;
  };

  const breakeven = calculateBreakeven();
  const simulatedPnL = calculatePnLAtRate(simulatedRate);

  // Improved: Token Logo Component
  const USDCLogo = () => (
    <div className="relative w-6 h-6 rounded-full bg-gradient-to-br from-blue-500 via-blue-600 to-blue-700 flex items-center justify-center shadow-md ring-2 ring-blue-300 dark:ring-blue-800">
      <DollarSign className="w-3.5 h-3.5 text-white font-bold" strokeWidth={3} />
    </div>
  );

  const YTLogo = () => (
    <div className="relative w-6 h-6 rounded-full bg-gradient-to-br from-emerald-400 via-green-500 to-emerald-600 flex items-center justify-center shadow-md ring-2 ring-emerald-300 dark:ring-emerald-800">
      <div className="text-white text-[9px] font-extrabold">YT</div>
    </div>
  );

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
        {/* Position Selector - Improved Colors */}
        <div className="grid grid-cols-2 gap-2 p-1 bg-gray-100 dark:bg-[#0d1117] rounded-lg">
          <button
            onClick={() => setSwapMode('fixed')}
            className={`flex items-center justify-center gap-1.5 py-2 px-3 rounded-md text-xs font-medium transition-all ${
              swapMode === 'fixed'
                ? 'bg-gradient-to-br from-emerald-50 to-green-50 dark:from-emerald-950/40 dark:to-green-950/40 text-emerald-700 dark:text-emerald-400 shadow-sm ring-1 ring-emerald-200 dark:ring-emerald-800'
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
                ? 'bg-gradient-to-br from-rose-50 to-red-50 dark:from-rose-950/40 dark:to-red-950/40 text-rose-700 dark:text-rose-400 shadow-sm ring-1 ring-rose-200 dark:ring-rose-800'
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
              className="w-full px-3 py-2.5 pr-24 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400"
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
              <USDCLogo />
              <span className="text-sm font-semibold text-gray-900 dark:text-white">USDC</span>
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
            <span className="text-gray-500 dark:text-gray-400">{swapMode === 'fixed' ? 'Buying' : 'Selling'} YT</span>
          </div>
          <div className="relative">
            <input
              type="text"
              value={estimatedOutput}
              readOnly
              placeholder="0.00"
              className="w-full px-3 py-2.5 pr-20 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white"
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
              <YTLogo />
              <span className="text-sm font-semibold text-gray-900 dark:text-white">YT</span>
            </div>
          </div>
        </div>

        {/* Breakeven Display - Compact */}
        {showScenarios && (
          <div className="flex items-center justify-between p-2.5 bg-gradient-to-br from-purple-50 to-violet-50 dark:from-purple-950/30 dark:to-violet-950/30 rounded-lg border border-purple-200 dark:border-purple-800/50 shadow-sm">
            <div className="flex items-center gap-1.5">
              <Calculator className="w-4 h-4 text-purple-600 dark:text-purple-400" />
              <span className="text-xs font-semibold text-gray-900 dark:text-white">Breakeven</span>
              <Tooltip
                id="breakeven"
                title="Breakeven Rate"
                description="The yield rate where you neither profit nor lose."
              />
            </div>
            <span className="text-base font-bold text-purple-600 dark:text-purple-400">
              {breakeven.toFixed(2)}%
            </span>
          </div>
        )}

        {/* Collateral Warning */}
        {swapMode === 'variable' && parseFloat(inputAmount) > 0 && (
          <div className="flex items-start gap-2 p-2.5 bg-gradient-to-br from-amber-50 to-orange-50 dark:from-amber-950/30 dark:to-orange-950/30 rounded-lg border border-amber-200 dark:border-amber-800/50 shadow-sm">
            <AlertTriangle className="w-4 h-4 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
            <div className="text-xs text-amber-900 dark:text-amber-200">
              <span className="font-semibold">Collateral Required:</span> {(parseFloat(inputAmount) * 0.1).toFixed(2)} USDC
            </div>
          </div>
        )}

        {/* Advanced Mode: Interactive P&L Simulator */}
        {advancedMode && showScenarios && (
          <div className="p-3 bg-gradient-to-br from-gray-50 to-slate-50 dark:from-[#0d1117] dark:to-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d] space-y-3 shadow-sm">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-gray-700 dark:text-gray-300">📊 P&L Simulator</span>
              <span className="text-xs text-gray-500 dark:text-gray-500">Interactive</span>
            </div>
            
            {/* Rate Slider */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs">
                <span className="text-gray-600 dark:text-gray-400">Yield Rate at Maturity</span>
                <span className="font-bold text-gray-900 dark:text-white text-sm">{simulatedRate.toFixed(2)}%</span>
              </div>
              <input
                type="range"
                min="0"
                max="15"
                step="0.25"
                value={simulatedRate}
                onChange={(e) => setSimulatedRate(parseFloat(e.target.value))}
                className="w-full h-2 bg-gray-200 dark:bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-600"
              />
              <div className="flex justify-between text-xs text-gray-500 dark:text-gray-400 font-medium">
                <span>0%</span>
                <span>7.5%</span>
                <span>15%</span>
              </div>
            </div>

            {/* P&L Result - Much Improved Colors */}
            <div className={`p-3 rounded-lg shadow-md ${
              simulatedPnL >= 0 
                ? 'bg-gradient-to-br from-emerald-100 to-green-100 dark:from-emerald-900/40 dark:to-green-900/40 border-2 border-emerald-300 dark:border-emerald-700'
                : 'bg-gradient-to-br from-rose-100 to-red-100 dark:from-rose-900/40 dark:to-red-900/40 border-2 border-rose-300 dark:border-rose-700'
            }`}>
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-gray-700 dark:text-gray-300">
                  P&L at {simulatedRate.toFixed(2)}%
                </span>
                <div className="flex items-center gap-1.5">
                  <span className={`text-xl font-extrabold ${
                    simulatedPnL >= 0
                      ? 'text-emerald-700 dark:text-emerald-300'
                      : 'text-rose-700 dark:text-rose-300'
                  }`}>
                    {simulatedPnL >= 0 ? '+' : ''}{simulatedPnL.toFixed(2)}
                  </span>
                  <span className="text-xs font-medium text-gray-600 dark:text-gray-400">USDC</span>
                </div>
              </div>
            </div>

            {/* Visual Gradient Bar - Much Improved Colors */}
            <div className="space-y-2">
              <div className="relative h-10 rounded-lg overflow-hidden shadow-md border border-gray-300 dark:border-gray-600">
                {/* Much improved gradient with vibrant colors */}
                <div className={`absolute inset-0 ${
                  isLongPosition 
                    ? 'bg-gradient-to-r from-rose-500 via-yellow-200 via-50% to-emerald-500'
                    : 'bg-gradient-to-r from-emerald-500 via-yellow-200 via-50% to-rose-500'
                }`} />
                
                {/* Breakeven Marker - Improved */}
                <div 
                  className="absolute top-0 bottom-0 w-1 bg-purple-700 dark:bg-purple-400 z-10 shadow-lg"
                  style={{ left: `${Math.min(100, (breakeven / 15) * 100)}%` }}
                >
                  <div className="absolute -top-6 left-1/2 -translate-x-1/2 bg-purple-600 dark:bg-purple-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded whitespace-nowrap shadow-md">
                    BE {breakeven.toFixed(1)}%
                  </div>
                </div>
                
                {/* Implied Rate Marker - Improved */}
                <div 
                  className="absolute top-0 bottom-0 w-1 bg-gray-900 dark:bg-white z-10 shadow-lg"
                  style={{ left: `${(impliedRate / 15) * 100}%` }}
                >
                  <div className="absolute -top-6 left-1/2 -translate-x-1/2 bg-gray-800 dark:bg-gray-200 text-white dark:text-gray-900 text-[10px] font-bold px-1.5 py-0.5 rounded whitespace-nowrap shadow-md">
                    Implied {impliedRate}%
                  </div>
                </div>
                
                {/* Simulated Rate Marker - Much More Visible */}
                <div 
                  className="absolute top-0 bottom-0 w-1.5 bg-blue-600 dark:bg-blue-400 shadow-2xl z-20 rounded-full"
                  style={{ left: `${(simulatedRate / 15) * 100}%` }}
                >
                  <div className="absolute top-1/2 -translate-y-1/2 -left-1.5 w-4 h-4 bg-blue-600 dark:bg-blue-400 rounded-full border-2 border-white shadow-xl" />
                </div>
              </div>
              <div className="flex justify-between text-xs text-gray-600 dark:text-gray-400 font-semibold px-1">
                <span className="flex items-center gap-1">
                  {isLongPosition ? '📉 Loss Zone' : '💰 Profit Zone'}
                </span>
                <span className="flex items-center gap-1">
                  {isLongPosition ? '💰 Profit Zone' : '📉 Loss Zone'}
                </span>
              </div>
            </div>
          </div>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!inputAmount || parseFloat(inputAmount) === 0 || isLoading}
          className="w-full py-3 bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 disabled:from-gray-300 disabled:to-gray-400 dark:disabled:from-gray-700 dark:disabled:to-gray-800 text-white font-semibold rounded-lg transition-all disabled:cursor-not-allowed text-sm shadow-md hover:shadow-lg"
        >
          {isLoading ? 'Processing...' : parseFloat(inputAmount) === 0 ? 'Enter amount' : 'Execute Swap'}
        </button>
      </div>
    </div>
  );
}
