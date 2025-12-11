'use client';

import React, { createContext, useContext, useState, ReactNode } from 'react';

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
}

const SwapContext = createContext<SwapContextType | undefined>(undefined);

export function SwapProvider({ children }: { children: ReactNode }) {
  const [swapMode, setSwapMode] = useState<SwapMode>('fixed');
  const [inputAmount, setInputAmount] = useState('');
  const [outputAmount, setOutputAmount] = useState('');
  const [isLoading, setIsLoading] = useState(false);

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
