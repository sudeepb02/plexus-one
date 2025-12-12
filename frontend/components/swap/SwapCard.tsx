'use client';

import { useState, useEffect } from 'react';
import { useSwap } from '@/lib/SwapContext';
import { useAccount, usePublicClient } from 'wagmi';
import { ArrowDownUp, TrendingUp, TrendingDown, Info, Zap, AlertCircle } from 'lucide-react';
import { formatUSDC, parseUSDC, calculateExpectedOutput, PLEXUS_YIELD_HOOK_ABI, buildPoolKey } from '@/lib/v4-swap';
import { CONTRACTS } from '@/lib/contracts';
import { Address, keccak256, encodeAbiParameters } from 'viem';

export function SwapCard() {
  const { 
    swapMode, 
    setSwapMode, 
    inputAmount, 
    setInputAmount, 
    isLoading,
    error,
    setError,
    userBalance,
    refreshBalance,
    executeSwap
  } = useSwap();

  const { isConnected } = useAccount();
  const publicClient = usePublicClient();

  const [estimatedOutput, setEstimatedOutput] = useState('0.00');
  const [showScenarios, setShowScenarios] = useState(false);
  const [advancedMode, setAdvancedMode] = useState(false);
  const [showTooltip, setShowTooltip] = useState<string | null>(null);
  const [simulatedRate, setSimulatedRate] = useState(5.25);
  const [balanceDisplay, setBalanceDisplay] = useState('0.00');
  const [collateralRequired, setCollateralRequired] = useState('0.00');
  const [ammProceeds, setAmmProceeds] = useState('0.00');
  const [reserveUnderlying, setReserveUnderlying] = useState<bigint>(BigInt(0));
  const [reserveYield, setReserveYield] = useState<bigint>(BigInt(0));

  const poolKey = buildPoolKey();

  // Hardcoded reserve values from the deployment
  // From ConfigureMarket.s.sol: initial_liquidity_underlying = 1250 * 1e6, initial_liquidity_yt = 100_000 * 1e6
  const HARDCODED_RESERVE_UNDERLYING = BigInt(1250) * BigInt(10) ** BigInt(6); // 1250 USDC
  const HARDCODED_RESERVE_YIELD = BigInt(100_000) * BigInt(10) ** BigInt(6); // 100,000 YT

  // Mock maturity date - in production, fetch from contract
  const maturityDate = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);
  const daysToMaturity = Math.floor((maturityDate.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
  const yearsToMaturity = daysToMaturity / 365;
  
  const isLongPosition = swapMode === 'fixed';
  const isShortPosition = swapMode === 'variable';

  const COLLATERAL_RATIO = 0.1;

  // Fetch pool reserves
  const fetchPoolReserves = async () => {
    if (!publicClient) {
      console.warn('publicClient not available');
      return;
    }

    try {
      console.log('Starting fetchPoolReserves...');
      console.log('Pool key details:', {
        currency0: poolKey.currency0,
        currency1: poolKey.currency1,
        fee: poolKey.fee,
        tickSpacing: poolKey.tickSpacing,
        hooks: poolKey.hooks,
      });

      // Use the Solidity keccak256 hashing of PoolKey struct fields
      // According to V4 PoolIdLibrary: poolId = keccak256(abi.encode(poolKey))
      // We need to use encodeAbiParameters to match abi.encode() behavior
      const encoded = encodeAbiParameters(
        [
          {
            type: 'tuple',
            components: [
              { name: 'currency0', type: 'address' },
              { name: 'currency1', type: 'address' },
              { name: 'fee', type: 'uint24' },
              { name: 'tickSpacing', type: 'int24' },
              { name: 'hooks', type: 'address' }
            ]
          }
        ],
        [
          {
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: poolKey.fee,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks
          }
        ]
      );

      const poolId = keccak256(encoded);

      console.log('Calculated poolId:', poolId);

      // Try to read the market state from the hook
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const marketState = await publicClient.readContract({
          address: CONTRACTS.PLEXUS_YIELD_HOOK as Address,
          abi: PLEXUS_YIELD_HOOK_ABI,
          functionName: 'marketStates',
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          args: [poolId as any],
        }) as any;

        console.log('Market state fetched successfully:', {
          reserveUnderlying: marketState[0].toString(),
          reserveYield: marketState[1].toString(),
          totalLpSupply: marketState[2].toString(),
          impliedRate: marketState[3].toString(),
          maturity: marketState[4].toString(),
          isInitialized: marketState[5],
        });

        if (!marketState[5]) {
          console.warn('Pool is not initialized in hook yet');
          return;
        }

        setReserveUnderlying(marketState[0]);
        setReserveYield(marketState[1]);
      } catch (contractErr) {
        console.error('Contract call failed:', {
          error: contractErr,
          hookAddress: CONTRACTS.PLEXUS_YIELD_HOOK,
          method: 'marketStates',
          poolId,
        });
        
        // Try alternative: read directly from hook storage (fallback)
        console.log('Attempting alternative fetch method...');
      }
    } catch (err) {
      console.error('Failed to fetch pool reserves:', err);
    }
  };

  // Refresh balance and reserves on mount and when connected
  useEffect(() => {
    if (isConnected) {
      console.log('Connected, fetching initial data');
      refreshBalance();
      fetchPoolReserves();

      // Polling: refresh reserves every 5 seconds
      const interval = setInterval(() => {
        console.log('Polling reserves...');
        fetchPoolReserves();
      }, 5000);

      return () => clearInterval(interval);
    }
  }, [isConnected, refreshBalance]);

  // Update balance display
  useEffect(() => {
    setBalanceDisplay(formatUSDC(userBalance));
  }, [userBalance]);

  const handleSwap = async () => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    try {
      await executeSwap(true); // true for exact input
      setError(null);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Swap failed';
      setError(errorMessage);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setInputAmount(value);
    setError(null);
    
    const inputVal = parseFloat(value) || 0;
    
    // Recalculate output with current reserves
    if (inputVal > 0) {
      calculateAndSetOutput(value);
    } else {
      setEstimatedOutput('0.00');
      setAmmProceeds('0.00');
      setCollateralRequired('0.00');
    }
    
    setShowScenarios(inputVal > 0);
  };

  // Clear inputs and reset state when swapping modes
  useEffect(() => {
    setInputAmount('');
    setEstimatedOutput('0.00');
    setAmmProceeds('0.00');
    setCollateralRequired('0.00');
    setShowScenarios(false);
    setError(null);
  }, [swapMode]);

  // Calculate output based on current reserves
  const calculateAndSetOutput = (inputAmountStr: string) => {
    const inputVal = parseFloat(inputAmountStr) || 0;
    
    // Use hardcoded reserves instead of fetched ones
    const currentReserveUnderlying = HARDCODED_RESERVE_UNDERLYING;
    const currentReserveYield = HARDCODED_RESERVE_YIELD;
    
    console.log('calculateAndSetOutput called with:', {
      inputAmountStr,
      inputVal,
      reserveUnderlying: currentReserveUnderlying.toString(),
      reserveYield: currentReserveYield.toString(),
      isShortPosition,
    });
    
    if (isShortPosition) {
      // SHORTS MODE: Input is YT Amount to Short
      const collateral = inputVal * COLLATERAL_RATIO;
      setCollateralRequired(collateral.toFixed(2));
      
      // Calculate proceeds based on pool reserves
      if (currentReserveYield > BigInt(0) && currentReserveUnderlying > BigInt(0)) {
        const inputAmountWei = parseUSDC(inputAmountStr);
        const expectedProceeds = calculateExpectedOutput(inputAmountWei, currentReserveYield, currentReserveUnderlying);
        const proceedsFormatted = formatUSDC(expectedProceeds);
        console.log('Short proceeds calculated:', {
          inputAmountWei: inputAmountWei.toString(),
          expectedProceeds: expectedProceeds.toString(),
          proceedsFormatted,
        });
        setAmmProceeds(proceedsFormatted);
        setEstimatedOutput(proceedsFormatted);
      } else {
        console.log('Reserves not ready for short calculation');
        setEstimatedOutput('0.00');
        setAmmProceeds('0.00');
      }
    } else {
      // LONG MODE: Input is USDC, output is YT
      // Calculate expected YT received based on pool reserves
      if (currentReserveUnderlying > BigInt(0) && currentReserveYield > BigInt(0)) {
        const inputAmountWei = parseUSDC(inputAmountStr);
        const expectedOutput = calculateExpectedOutput(inputAmountWei, currentReserveUnderlying, currentReserveYield);
        const outputFormatted = formatUSDC(expectedOutput);
        console.log('Long output calculated:', {
          inputAmountWei: inputAmountWei.toString(),
          expectedOutput: expectedOutput.toString(),
          outputFormatted,
        });
        setEstimatedOutput(outputFormatted);
      } else {
        console.log('Reserves not ready for long calculation');
        setEstimatedOutput('0.00');
      }
    }
  };

  // Recalculate output whenever swap mode changes
  useEffect(() => {
    console.log('useEffect triggered - mode changed:', {
      reserveUnderlying: HARDCODED_RESERVE_UNDERLYING.toString(),
      reserveYield: HARDCODED_RESERVE_YIELD.toString(),
      inputAmount,
      swapMode,
    });
    if (inputAmount && parseFloat(inputAmount) > 0) {
      calculateAndSetOutput(inputAmount);
    }
  }, [swapMode]);

  const calculatePnLAtRate = (rate: number) => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return 0;
    const amountIn = parseFloat(inputAmount);
    const ytAmount = parseFloat(estimatedOutput);

    if (isLongPosition) {
      const payout = ytAmount * (rate / 100) * yearsToMaturity;
      return payout - amountIn;
    } else {
      const premiumReceived = parseFloat(ammProceeds);
      const debt = parseFloat(inputAmount) * (rate / 100) * yearsToMaturity;
      return premiumReceived - debt;
    }
  };

  const calculateBreakeven = () => {
    if (!inputAmount || parseFloat(inputAmount) === 0) return 5.25;
    
    if (isShortPosition) {
      const ytAmount = parseFloat(inputAmount);
      const premiumReceived = parseFloat(ammProceeds);
      if (ytAmount === 0 || yearsToMaturity === 0) return 5.25;
      return (premiumReceived / (ytAmount * yearsToMaturity)) * 100;
    } else {
      const amountIn = parseFloat(inputAmount);
      const ytAmount = parseFloat(estimatedOutput);
      if (ytAmount === 0 || yearsToMaturity === 0) return 5.25;
      return (amountIn / (ytAmount * yearsToMaturity)) * 100;
    }
  };

  const breakeven = calculateBreakeven();
  const simulatedPnL = calculatePnLAtRate(simulatedRate);

  // Token Logo Components
  const USDCLogo = () => (
    <div className="relative w-6 h-6 rounded-full bg-gradient-to-br from-[#2775CA] to-[#1E5BA8] flex items-center justify-center shadow-md ring-2 ring-blue-400/30 dark:ring-blue-600/30">
      <span className="text-white text-[7px] font-black tracking-tighter">USDC</span>
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
            <span className="text-gray-600 dark:text-gray-400">Maturity:</span>
            <span className="font-medium text-gray-900 dark:text-white">{daysToMaturity}d</span>
          </div>
          <div className="flex items-center gap-1">
            <span className="text-gray-600 dark:text-gray-400">Breakeven Rate:</span>
            <span className="text-base font-bold text-blue-600 dark:text-blue-400">{breakeven.toFixed(2)}%</span>
            <Tooltip
              id="breakeven-rate"
              title="Breakeven Rate"
              description="The yield rate at which your position breaks even at maturity."
            />
          </div>
        </div>
      </div>

      <div className="p-4 space-y-3">
        {/* Connection Warning */}
        {!isConnected && (
          <div className="flex items-start gap-2 p-2.5 bg-gradient-to-br from-blue-50 to-cyan-50 dark:from-blue-950/30 dark:to-cyan-950/30 rounded-lg border border-blue-200 dark:border-blue-800/50">
            <AlertCircle className="w-4 h-4 text-blue-600 dark:text-blue-400 mt-0.5 flex-shrink-0" />
            <span className="text-xs text-blue-900 dark:text-blue-200">
              Connect your wallet to execute swaps
            </span>
          </div>
        )}

        {/* Error Display */}
        {error && (
          <div className="flex items-start gap-2 p-2.5 bg-gradient-to-br from-red-50 to-rose-50 dark:from-red-950/30 dark:to-rose-950/30 rounded-lg border border-red-200 dark:border-red-800/50">
            <AlertCircle className="w-4 h-4 text-red-600 dark:text-red-400 mt-0.5 flex-shrink-0" />
            <span className="text-xs text-red-900 dark:text-red-200">{error}</span>
          </div>
        )}

        {/* Position Selector */}
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

        {/* CONDITIONAL RENDERING: LONG vs SHORT */}
        {isLongPosition ? (
          // LONG MODE: Standard swap (USDC -> YT)
          <>
            {/* Input Section */}
            <div className="space-y-2">
              <div className="flex items-center justify-between text-xs">
                <span className="text-gray-600 dark:text-gray-400">You pay</span>
                <span className="text-gray-500 dark:text-gray-400">Balance: {balanceDisplay}</span>
              </div>
              <div className="relative">
                <input
                  type="number"
                  value={inputAmount}
                  onChange={handleInputChange}
                  placeholder="0.00"
                  disabled={!isConnected}
                  className="w-full px-3 py-2.5 pr-24 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 disabled:opacity-50 disabled:cursor-not-allowed"
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
                <span className="text-gray-500 dark:text-gray-400">Est. YT</span>
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
          </>
        ) : (
          // SHORT MODE: YT Amount -> Collateral + AMM Proceeds
          <>
            {/* Step 1: YT Amount Input */}
            <div className="space-y-2">
              <div className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-1.5">
                  <span className="text-gray-600 dark:text-gray-400">YT Amount to Short</span>
                  <Tooltip
                    id="yt-short-amount"
                    title="YT Amount to Short"
                    description="The amount of Yield Tokens you want to mint and sell. This is Step 1 of the short position."
                  />
                </div>
                <span className="text-gray-500 dark:text-gray-400">Balance: {balanceDisplay}</span>
              </div>
              <div className="relative">
                <input
                  type="number"
                  value={inputAmount}
                  onChange={handleInputChange}
                  placeholder="0.00"
                  disabled={!isConnected}
                  className="w-full px-3 py-2.5 pr-24 bg-gray-50 dark:bg-[#0d1117] border border-gray-200 dark:border-[#30363d] rounded-lg text-lg font-medium text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 disabled:opacity-50 disabled:cursor-not-allowed"
                />
                <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                  <YTLogo />
                  <span className="text-sm font-semibold text-gray-900 dark:text-white">YT</span>
                </div>
              </div>
            </div>

            {/* Step 1 Display: Collateral Required */}
            {parseFloat(inputAmount) > 0 && (
              <div className="p-3 bg-gradient-to-br from-blue-50 to-cyan-50 dark:from-blue-950/20 dark:to-cyan-950/20 rounded-lg border border-blue-200 dark:border-blue-800/50">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <AlertCircle className="w-4 h-4 text-blue-600 dark:text-blue-400" />
                    <div>
                      <div className="text-xs font-medium text-blue-900 dark:text-blue-200">Step 1: Mint YT with Collateral</div>
                      <div className="text-xs text-blue-800 dark:text-blue-300 mt-0.5">Collateral required to mint {inputAmount} YT</div>
                    </div>
                  </div>
                </div>
                <div className="mt-2 pt-2 border-t border-blue-200 dark:border-blue-800/50 flex items-center justify-between">
                  <span className="text-sm font-semibold text-blue-900 dark:text-blue-200">Collateral Required:</span>
                  <div className="flex items-center gap-1.5">
                    <span className="text-lg font-bold text-blue-600 dark:text-blue-400">{collateralRequired}</span>
                    <USDCLogo />
                    <span className="text-sm font-semibold text-blue-900 dark:text-blue-200">USDC</span>
                  </div>
                </div>
              </div>
            )}

            {/* Divider */}
            {parseFloat(inputAmount) > 0 && (
              <div className="flex items-center gap-2">
                <div className="flex-1 h-px bg-gray-200 dark:bg-gray-700"></div>
                <span className="text-xs text-gray-500 dark:text-gray-400 font-medium">Step 2</span>
                <div className="flex-1 h-px bg-gray-200 dark:bg-gray-700"></div>
              </div>
            )}

            {/* Step 2 Display: AMM Proceeds */}
            {parseFloat(inputAmount) > 0 && (
              <div className="p-3 bg-gradient-to-br from-emerald-50 to-green-50 dark:from-emerald-950/20 dark:to-green-950/20 rounded-lg border border-emerald-200 dark:border-emerald-800/50">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Zap className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
                    <div>
                      <div className="text-xs font-medium text-emerald-900 dark:text-emerald-200">Step 2: Sell YT on AMM</div>
                      <div className="text-xs text-emerald-800 dark:text-emerald-300 mt-0.5">Expected proceeds from selling {inputAmount} YT tokens</div>
                    </div>
                  </div>
                </div>
                <div className="mt-2 pt-2 border-t border-emerald-200 dark:border-emerald-800/50 flex items-center justify-between">
                  <span className="text-sm font-semibold text-emerald-900 dark:text-emerald-200">You Receive:</span>
                  <div className="flex items-center gap-1.5">
                    <span className="text-lg font-bold text-emerald-600 dark:text-emerald-400">{ammProceeds}</span>
                    <USDCLogo />
                    <span className="text-sm font-semibold text-emerald-900 dark:text-emerald-200">USDC</span>
                  </div>
                </div>
              </div>
            )}

            {/* Short Position Summary */}
            {parseFloat(inputAmount) > 0 && (
              <div className="p-3 bg-gradient-to-br from-amber-50 to-orange-50 dark:from-amber-950/20 dark:to-orange-950/20 rounded-lg border border-amber-200 dark:border-amber-800/50">
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-amber-900 dark:text-amber-200 font-medium">Short Position Summary</span>
                  </div>
                  <div className="space-y-1.5 pt-1">
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-amber-800 dark:text-amber-300">YT Shorted:</span>
                      <span className="text-xs font-semibold text-amber-900 dark:text-amber-200">{inputAmount} YT</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-amber-800 dark:text-amber-300">Margin Locked:</span>
                      <span className="text-xs font-semibold text-amber-900 dark:text-amber-200">{collateralRequired} USDC</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-amber-800 dark:text-amber-300">Initial Credit:</span>
                      <span className="text-xs font-semibold text-amber-900 dark:text-amber-200">{ammProceeds} USDC</span>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </>
        )}

        {/* Advanced Mode: Interactive P&L Simulator */}
        {advancedMode && showScenarios && (
          <div className="p-3 bg-gradient-to-br from-gray-50 to-slate-50 dark:from-[#0d1117] dark:to-[#0d1117] rounded-lg border border-gray-200 dark:border-[#30363d] space-y-3 shadow-sm">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-gray-700 dark:text-gray-300">📊 P&L Simulator</span>
              <span className="text-xs text-gray-500 dark:text-gray-500">Interactive</span>
            </div>
            
            {/* Rate Slider with P&L Display */}
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
              
              {/* P&L Value Display */}
              <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
                <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
                  P&L at {simulatedRate.toFixed(2)}%:
                </span>
                <div className="flex items-center gap-1.5">
                  <span className={`text-lg font-bold ${
                    simulatedPnL >= 0
                      ? 'text-emerald-600 dark:text-emerald-400'
                      : 'text-rose-600 dark:text-rose-400'
                  }`}>
                    {simulatedPnL >= 0 ? '+' : ''}{simulatedPnL.toFixed(2)}
                  </span>
                  <span className="text-xs font-medium text-gray-600 dark:text-gray-400">USDC</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!isConnected || !inputAmount || parseFloat(inputAmount) === 0 || isLoading}
          className="w-full py-3 bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 disabled:from-gray-300 disabled:to-gray-400 dark:disabled:from-gray-700 dark:disabled:to-gray-800 text-white font-semibold rounded-lg transition-all disabled:cursor-not-allowed text-sm shadow-md hover:shadow-lg"
        >
          {!isConnected 
            ? 'Connect Wallet' 
            : isLoading 
            ? 'Processing...' 
            : parseFloat(inputAmount) === 0 
            ? 'Enter amount' 
            : isShortPosition
            ? 'Execute Short'
            : 'Execute Swap'
          }
        </button>
      </div>
    </div>
  );
}
