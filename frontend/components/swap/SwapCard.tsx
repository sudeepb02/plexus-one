'use client';

import { useState } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { ArrowDownUp, TrendingUp, TrendingDown, Info, ChevronDown, ChevronUp, AlertTriangle, Clock, Calculator } from 'lucide-react';

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
  const maturityDate = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000); // 180 days from now
  const daysToMaturity = Math.floor((maturityDate.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
  
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
      const bullishPnl = ytAmount * (0.07 - impliedRate / 100) - amount;
      const bearishPnl = ytAmount * (0.03 - impliedRate / 100) - amount;
      return {
        bullish: { rate: 7, pnl: bullishPnl },
        bearish: { rate: 3, pnl: bearishPnl }
      };
    } else {
      // Short: Profit if actual yield < implied rate
      const premium = amount * (impliedRate / 100);
      const bullishPnl = premium - (ytAmount * 0.07);
      const bearishPnl = premium - (ytAmount * 0.03);
      return {
        bullish: { rate: 7, pnl: bullishPnl },
        bearish: { rate: 3, pnl: bearishPnl }
      };
    }
  };

  // Calculate collateral requirements for short positions
  const calculateCollateral = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return { required: 0, ratio: 0 };
    
    const amount = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);
    
    // MIN_COLLATERAL_RATIO = 0.1 (10% of notional)
    const minCollateral = ytAmount * 0.1;
    
    return {
      required: minCollateral,
      ratio: 10, // 10%
      provided: amount,
      isAdequate: amount >= minCollateral
    };
  };

  // Calculate max gain/loss
  const calculateMaxPnL = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) {
      return { maxGain: 0, maxLoss: 0 };
    }

    const amount = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);

    if (isLongPosition) {
      // Long position
      // Max gain: theoretically unlimited (if rates go to 100%)
      // Practical max gain at 20% yield
      const maxGain = ytAmount * (0.20 - impliedRate / 100);
      // Max loss: full cost if rates go to 0%
      const maxLoss = amount;
      
      return { maxGain, maxLoss };
    } else {
      // Short position
      // Max gain: premium received if rates go to 0%
      const premium = amount * (impliedRate / 100);
      const maxGain = premium;
      // Max loss: if rates go to 20%
      const maxLoss = (ytAmount * 0.20) - premium;
      
      return { maxGain, maxLoss };
    }
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

  // Calculate time decay (theta)
  const calculateTimeDecay = () => {
    const totalDays = 365;
    const remainingDays = daysToMaturity;
    const timeRemaining = remainingDays / totalDays;
    
    return {
      percentRemaining: (timeRemaining * 100).toFixed(1),
      dailyDecay: ((1 / remainingDays) * 100).toFixed(3),
      valueAtMaturity: timeRemaining
    };
  };

  const scenarios = calculateScenarios();
  const collateral = calculateCollateral();
  const pnl = calculateMaxPnL();
  const breakeven = calculateBreakeven();
  const timeDecay = calculateTimeDecay();
  const simulatedPnL = calculatePnLAtRate(simulatedRate);

  const Tooltip = ({ id, title, description }: { id: string; title: string; description: string }) => (
    <button
      onMouseEnter={() => setShowTooltip(id)}
      onMouseLeave={() => setShowTooltip(null)}
      className="relative text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300"
    >
      <Info className="w-3.5 h-3.5" />
      {showTooltip === id && (
        <div className="absolute z-50 w-64 p-3 bg-gray-900 dark:bg-gray-800 text-white text-xs rounded-lg shadow-lg -left-28 top-6">
          <p className="font-semibold mb-1">{title}</p>
          <p className="text-gray-300">{description}</p>
        </div>
      )}
    </button>
  );

  return (
    <div className="w-full bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      {/* Header */}
      <div className="border-b border-gray-200 dark:border-[#30363d] p-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Interest Rate Swap</h2>
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
              Take a position on future yield rates
            </p>
          </div>
          <button
            onClick={() => setAdvancedMode(!advancedMode)}
            className="flex items-center gap-1 text-xs text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300"
          >
            {advancedMode ? 'Simple' : 'Advanced'}
            {advancedMode ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
          </button>
        </div>
      </div>

      <div className="p-4 space-y-4">
        {/* Time to Maturity & Theta */}
        <div className="grid grid-cols-2 gap-2">
          <div className="flex items-center justify-between p-2.5 bg-gray-50 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d]">
            <div className="flex items-center gap-2">
              <Clock className="w-3.5 h-3.5 text-gray-500 dark:text-gray-400" />
              <span className="text-xs text-gray-600 dark:text-gray-400">Maturity</span>
            </div>
            <span className="text-xs font-medium text-gray-900 dark:text-white">
              {daysToMaturity}d
            </span>
          </div>
          
          {advancedMode && (
            <div className="flex items-center justify-between p-2.5 bg-gray-50 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d]">
              <div className="flex items-center gap-1">
                <span className="text-xs text-gray-600 dark:text-gray-400">Theta</span>
                <Tooltip
                  id="theta"
                  title="Time Decay (Theta)"
                  description="Rate at which your position loses time value each day as you approach maturity."
                />
              </div>
              <span className="text-xs font-medium text-gray-900 dark:text-white">
                -{timeDecay.dailyDecay}%/day
              </span>
            </div>
          )}
        </div>

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
              <Tooltip
                id="implied-rate"
                title="Implied Rate"
                description="The market's current expectation for future yields. This is your breakeven point - you profit if actual rates differ from this."
              />
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

        {/* Breakeven Display */}
        {showScenarios && (
          <div className="p-3 bg-purple-50 dark:bg-purple-950/20 rounded-lg border border-purple-200 dark:border-purple-900/50">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Calculator className="w-4 h-4 text-purple-600 dark:text-purple-400" />
                <span className="text-xs font-medium text-gray-900 dark:text-white">
                  Your Breakeven Rate
                </span>
                <Tooltip
                  id="breakeven"
                  title="Breakeven Rate"
                  description="The actual yield rate at which you neither profit nor lose."
                />
              </div>
              <span className="text-base font-bold text-purple-600 dark:text-purple-400">
                {breakeven.toFixed(2)}%
              </span>
            </div>
          </div>
        )}

        {/* Collateral Warning for Short Positions */}
        {!isLongPosition && showScenarios && (
          <div className={`p-3 rounded-lg border ${
            collateral.isAdequate
              ? 'bg-blue-50 dark:bg-blue-950/20 border-blue-200 dark:border-blue-900/50'
              : 'bg-amber-50 dark:bg-amber-950/20 border-amber-200 dark:border-amber-900/50'
          }`}>
            <div className="flex items-start gap-2">
              <AlertTriangle className={`w-4 h-4 mt-0.5 flex-shrink-0 ${
                collateral.isAdequate 
                  ? 'text-blue-600 dark:text-blue-400'
                  : 'text-amber-600 dark:text-amber-400'
              }`} />
              <div className="flex-1">
                <p className="text-xs font-medium text-gray-900 dark:text-white mb-1">
                  Collateral Requirement
                </p>
                <div className="space-y-1 text-xs text-gray-600 dark:text-gray-400">
                  <div className="flex justify-between">
                    <span>Minimum required:</span>
                    <span className="font-medium">{collateral.required.toFixed(2)} USDC ({collateral.ratio}%)</span>
                  </div>
                  <div className="flex justify-between">
                    <span>You're providing:</span>
                    <span className={`font-medium ${
                      collateral.isAdequate 
                        ? 'text-green-600 dark:text-green-400' 
                        : 'text-amber-600 dark:text-amber-400'
                    }`}>
                      {collateral.provided.toFixed(2)} USDC
                    </span>
                  </div>
                </div>
                {!collateral.isAdequate && (
                  <p className="text-xs text-amber-600 dark:text-amber-400 mt-2">
                    ⚠️ Insufficient collateral. Position may be liquidated.
                  </p>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Interactive P&L Simulator - Advanced Mode */}
        {advancedMode && showScenarios && (
          <div className="p-3 bg-gray-50 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d] space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-gray-600 dark:text-gray-400">P&L Simulator</span>
              <span className="text-xs text-gray-500 dark:text-gray-500">Drag to test scenarios</span>
            </div>
            
            {/* Rate Slider */}
            <div className="space-y-2">
              <div className="flex items-center justify-between text-xs">
                <span className="text-gray-600 dark:text-gray-400">Simulated Yield Rate</span>
                <span className="font-semibold text-gray-900 dark:text-white">{simulatedRate.toFixed(2)}%</span>
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
              <div className="flex justify-between text-xs text-gray-500 dark:text-gray-400">
                <span>0%</span>
                <span>15%</span>
              </div>
            </div>

            {/* P&L Result */}
            <div className={`p-2.5 rounded-lg ${
              simulatedPnL >= 0 
                ? 'bg-green-50 dark:bg-green-950/20 border border-green-200 dark:border-green-900/50'
                : 'bg-red-50 dark:bg-red-950/20 border border-red-200 dark:border-red-900/50'
            }`}>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600 dark:text-gray-400">
                  P&L at {simulatedRate.toFixed(2)}% yield
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

            {/* Visual P&L Gradient Bar */}
            <div className="space-y-2">
              <div className="relative h-8 bg-gradient-to-r from-red-500 via-gray-300 to-green-500 rounded overflow-hidden">
                {/* Implied Rate Marker */}
                <div 
                  className="absolute top-0 bottom-0 w-0.5 bg-gray-900 dark:bg-white z-10"
                  style={{ left: `${(impliedRate / 15) * 100}%` }}
                >
                  <div className="absolute -top-5 left-1/2 -translate-x-1/2 text-xs font-bold text-gray-900 dark:text-white whitespace-nowrap">
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
                <span>{isLongPosition ? 'Loss' : 'Profit'} Zone</span>
                <span>{isLongPosition ? 'Profit' : 'Loss'} Zone</span>
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

        {/* Advanced Mode - Max Gain/Loss */}
        {advancedMode && showScenarios && (
          <div className="p-3 bg-gray-50 dark:bg-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d] space-y-2">
            <div className="flex items-center justify-between text-xs">
              <div className="flex items-center gap-1">
                <span className="text-gray-600 dark:text-gray-400">Max Potential Gain</span>
                <Tooltip
                  id="max-gain"
                  title="Maximum Gain"
                  description={isLongPosition 
                    ? "Theoretical maximum profit if rates reach 20%. Actual gains could be higher."
                    : "Maximum profit occurs when rates drop to 0%, limited to premium received."
                  }
                />
              </div>
              <span className="font-semibold text-green-600 dark:text-green-400">
                +{pnl.maxGain.toFixed(2)} USDC
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <div className="flex items-center gap-1">
                <span className="text-gray-600 dark:text-gray-400">Max Potential Loss</span>
                <Tooltip
                  id="max-loss"
                  title="Maximum Loss"
                  description={isLongPosition
                    ? "Maximum loss is your initial cost if rates drop to 0%."
                    : "Maximum loss if rates reach 20%. Maintain adequate collateral to avoid liquidation."
                  }
                />
              </div>
              <span className="font-semibold text-red-600 dark:text-red-400">
                -{pnl.maxLoss.toFixed(2)} USDC
              </span>
            </div>
          </div>
        )}

        {/* Educational Expandable - What am I buying? */}
        {advancedMode && (
          <details className="group">
            <summary className="cursor-pointer text-xs font-medium text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 flex items-center gap-1">
              <span>What am I {isLongPosition ? 'buying' : 'selling'}?</span>
              <ChevronDown className="w-3 h-3 group-open:rotate-180 transition-transform" />
            </summary>
            <div className="mt-2 p-3 bg-gray-50 dark:bg-[#0d1117] rounded-lg text-xs text-gray-600 dark:text-gray-400 space-y-2">
              {isLongPosition ? (
                <>
                  <p>
                    <strong className="text-gray-900 dark:text-white">Yield Tokens (YT)</strong> represent a claim on future yield generated by the underlying asset.
                  </p>
                  <p>
                    By buying YT, you're betting that actual yields will exceed the current implied rate of {impliedRate}%. If correct, you profit from the difference.
                  </p>
                  <p className="text-amber-600 dark:text-amber-400">
                    ⚠️ If yields are lower than expected, you may lose part or all of your investment.
                  </p>
                </>
              ) : (
                <>
                  <p>
                    <strong className="text-gray-900 dark:text-white">Shorting</strong> means you mint and sell YT tokens, betting yields will be lower than {impliedRate}%.
                  </p>
                  <p>
                    You receive a premium upfront. If actual yields are below {impliedRate}%, you keep most of the premium as profit.
                  </p>
                  <p className="text-amber-600 dark:text-amber-400">
                    ⚠️ You must maintain sufficient collateral. If yields spike and your collateral is insufficient, your position may be liquidated.
                  </p>
                </>
              )}
            </div>
          </details>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!inputAmount || isLoading || (!isLongPosition && showScenarios && !collateral.isAdequate)}
          className={`w-full py-3 rounded-lg font-medium text-sm transition-all ${
            !inputAmount || isLoading || (!isLongPosition && showScenarios && !collateral.isAdequate)
              ? 'bg-gray-100 dark:bg-[#0d1117] text-gray-400 dark:text-gray-600 cursor-not-allowed border border-gray-200 dark:border-[#30363d]'
              : isLongPosition
              ? 'bg-green-600 hover:bg-green-700 text-white shadow-sm'
              : 'bg-red-600 hover:bg-red-700 text-white shadow-sm'
          }`}
        >
          {isLoading 
            ? 'Processing...' 
            : !inputAmount 
            ? 'Enter amount' 
            : (!isLongPosition && showScenarios && !collateral.isAdequate)
            ? 'Insufficient collateral'
            : `${isLongPosition ? 'Long' : 'Short'} ${impliedRate}%`
          }
        </button>
      </div>
    </div>
  );
}
