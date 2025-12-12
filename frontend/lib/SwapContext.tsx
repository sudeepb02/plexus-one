'use client';

import React, { createContext, useContext, useState, ReactNode } from 'react';
import { useAccount, usePublicClient, useWalletClient } from 'wagmi';
import { Address } from 'viem';
import { CONTRACTS } from './contracts';
import { 
  buildPoolKey, 
  isZeroForOne, 
  parseUSDC,
  formatUSDC,
  ERC20_ABI,
  encodeApproval,
  encodeSwapCall,
  PoolKey,
} from './v4-swap';

type SwapMode = 'fixed' | 'variable';

interface SwapContextType {
  swapMode: SwapMode;
  setSwapMode: (mode: SwapMode) => void;
  inputAmount: string;
  setInputAmount: (amount: string) => void;
  outputAmount: string;
  setOutputAmount: (amount: string) => void;
  isLoading: boolean;
  setIsLoading: (loading: boolean) => void;
  error: string | null;
  setError: (error: string | null) => void;
  userBalance: bigint;
  setUserBalance: (balance: bigint) => void;
  executeSwap: (isExactInput: boolean) => Promise<void>;
  refreshBalance: () => Promise<void>;
}

const SwapContext = createContext<SwapContextType | undefined>(undefined);

export function SwapProvider({ children }: { children: ReactNode }) {
  const { address: userAddress, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();

  const [swapMode, setSwapMode] = useState<SwapMode>('fixed');
  const [inputAmount, setInputAmount] = useState('');
  const [outputAmount, setOutputAmount] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [userBalance, setUserBalance] = useState<bigint>(BigInt(0));

  const poolKey = buildPoolKey();
  const SWAP_TEST_ADDRESS = '0x9140a78c1a137c7ff1c151ec8231272af78a99a4' as Address;

  // Refresh user balance
  const refreshBalance = async () => {
    if (!userAddress || !publicClient) return;

    try {
      const balance = await publicClient.readContract({
        address: CONTRACTS.MOCK_USDC as Address,
        abi: ERC20_ABI,
        functionName: 'balanceOf',
        args: [userAddress],
      }) as bigint;

      setUserBalance(balance);
    } catch (err) {
      console.error('Failed to refresh balance:', err);
    }
  };

  /**
   * Check current allowance and approve if necessary
   */
  const ensureApproval = async (
    tokenAddress: Address,
    spenderAddress: Address,
    requiredAmount: bigint
  ): Promise<void> => {
    if (!userAddress || !publicClient || !walletClient) {
      throw new Error('Wallet not connected');
    }

    try {
      // Check current allowance
      const currentAllowance = await publicClient.readContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: 'allowance',
        args: [userAddress, spenderAddress],
      }) as bigint;

      console.log(
        `Current allowance: ${currentAllowance.toString()}, Required: ${requiredAmount.toString()}`
      );

      // Only approve if current allowance is less than required amount
      if (currentAllowance < requiredAmount) {
        console.log('Approving token spend...');

        const approvalData = encodeApproval(spenderAddress, requiredAmount);

        const approvalTx = await walletClient.sendTransaction({
          account: userAddress,
          to: tokenAddress,
          data: approvalData,
        });

        console.log('Approval tx sent:', approvalTx);
        
        const receipt = await publicClient.waitForTransactionReceipt({ 
          hash: approvalTx,
          timeout: 60000,
        });

        if (receipt.status !== 'success') {
          throw new Error('Approval transaction failed');
        }
        
        console.log('Approval transaction confirmed');
      } else {
        console.log('Sufficient allowance already exists. Skipping approval.');
      }
    } catch (err) {
      console.error('Error during approval:', err);
      throw err;
    }
  };

  // Execute swap using SwapTest contract
  const executeSwap = async (isExactInput: boolean) => {
    if (!userAddress || !publicClient || !walletClient) {
      setError('Wallet not connected');
      return;
    }

    if (!inputAmount || inputAmount === '0') {
      setError('Please enter a valid amount');
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const amountIn = parseUSDC(inputAmount);
      
      // Determine swap direction
      const inputToken = swapMode === 'fixed' ? CONTRACTS.MOCK_USDC : CONTRACTS.YIELD_TOKEN;
      const zeroForOne = isZeroForOne(poolKey, inputToken as Address);

      // For exact input: amountSpecified is negative
      // For exact output: amountSpecified is positive
      const amountSpecified = isExactInput ? -amountIn : amountIn;

      console.log('Swap parameters:', {
        poolKey,
        amountSpecified: amountSpecified.toString(),
        zeroForOne,
        inputToken,
        swapTestAddress: SWAP_TEST_ADDRESS,
      });

      // Step 1: Approve token to SwapTest contract
      await ensureApproval(
        inputToken as Address,
        SWAP_TEST_ADDRESS,
        amountIn
      );

      // Step 2: Encode the swap call
      const swapCalldata = encodeSwapCall(
        poolKey,
        amountSpecified,
        zeroForOne,
        '0x' as any
      );

      console.log('Encoded swap call:', swapCalldata);

      // Step 3: Send swap transaction to SwapTest
      const swapTx = await walletClient.sendTransaction({
        account: userAddress,
        to: SWAP_TEST_ADDRESS,
        data: swapCalldata,
        value: BigInt(0),
      });

      console.log('Swap transaction sent:', swapTx);

      // Wait for confirmation
      const receipt = await publicClient.waitForTransactionReceipt({ 
        hash: swapTx,
        timeout: 60000,
      });

      console.log('Swap receipt:', receipt);

      if (receipt.status === 'success') {
        console.log('Swap successful!');
        setInputAmount('');
        setOutputAmount('');
        await refreshBalance();
      } else {
        setError('Swap transaction failed');
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Swap failed';
      setError(errorMessage);
      console.error('Swap error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <SwapContext.Provider
      value={{
        swapMode,
        setSwapMode,
        inputAmount,
        setInputAmount,
        outputAmount,
        setOutputAmount,
        isLoading,
        setIsLoading,
        error,
        setError,
        userBalance,
        setUserBalance,
        executeSwap,
        refreshBalance,
      }}
    >
      {children}
    </SwapContext.Provider>
  );
}

export function useSwap() {
  const context = useContext(SwapContext);
  if (context === undefined) {
    throw new Error('useSwap must be used within a SwapProvider');
  }
  return context;
}
