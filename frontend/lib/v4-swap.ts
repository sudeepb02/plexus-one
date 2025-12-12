import { 
  Address, 
  encodeFunctionData, 
  parseUnits, 
  formatUnits,
  Hex
} from 'viem';
import { CONTRACTS } from './contracts';

// ERC20 ABI
export const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable'
  },
  {
    name: 'allowance',
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' }
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view'
  },
  {
    name: 'balanceOf',
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view'
  }
] as const;

// SwapTest ABI - Matches the deployed contract
export const SWAP_TEST_ABI = [
  {
    name: 'swap',
    type: 'function',
    inputs: [
      {
        name: 'key',
        type: 'tuple',
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' },
        ],
      },
      {
        name: 'params',
        type: 'tuple',
        components: [
          { name: 'zeroForOne', type: 'bool' },
          { name: 'amountSpecified', type: 'int256' },
          { name: 'sqrtPriceLimitX96', type: 'uint160' },
        ],
      },
      {
        name: 'testSettings',
        type: 'tuple',
        components: [
          { name: 'takeClaims', type: 'bool' },
          { name: 'settleUsingBurn', type: 'bool' },
        ],
      },
      { name: 'hookData', type: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'payable'
  }
] as const;

// PlexusYieldHook ABI - for reading market state
export const PLEXUS_YIELD_HOOK_ABI = [
  {
    name: 'marketStates',
    type: 'function',
    inputs: [
      { name: 'poolId', type: 'bytes32' }
    ],
    outputs: [
      { name: 'reserveUnderlying', type: 'uint128' },
      { name: 'reserveYield', type: 'uint128' },
      { name: 'totalLpSupply', type: 'uint128' },
      { name: 'impliedRate', type: 'uint256' },
      { name: 'maturity', type: 'uint256' },
      { name: 'isInitialized', type: 'bool' },
      { name: 'hasPendingYield', type: 'bool' }
    ],
    stateMutability: 'view'
  }
] as const;

export interface PoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

export function buildPoolKey(): PoolKey {
  const mockUSDC = CONTRACTS.MOCK_USDC.toLowerCase();
  const yieldToken = CONTRACTS.YIELD_TOKEN.toLowerCase();

  const currency0 = mockUSDC < yieldToken ? CONTRACTS.MOCK_USDC : CONTRACTS.YIELD_TOKEN;
  const currency1 = mockUSDC < yieldToken ? CONTRACTS.YIELD_TOKEN : CONTRACTS.MOCK_USDC;

  return {
    currency0: currency0 as Address,
    currency1: currency1 as Address,
    fee: 500,
    tickSpacing: 60,
    hooks: CONTRACTS.PLEXUS_YIELD_HOOK as Address
  };
}

export function isZeroForOne(poolKey: PoolKey, inputToken: Address): boolean {
  return inputToken.toLowerCase() === poolKey.currency0.toLowerCase();
}

export function parseUSDC(amount: string): bigint {
  return parseUnits(amount, 6);
}

export function formatUSDC(amount: bigint): string {
  return formatUnits(amount, 6);
}

export function encodeApproval(spender: Address, amount: bigint): Hex {
  return encodeFunctionData({
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [spender, amount]
  });
}

/**
 * Calculate expected output amount based on pool reserves
 * Uses the same formula as the Solidity tests:
 * expectedOutput = (amountIn * reserveOutput) / reserveInput
 * 
 * @param amountIn - Input amount in wei
 * @param reserveInput - Reserve of input token in wei
 * @param reserveOutput - Reserve of output token in wei
 * @returns Expected output amount in wei
 */
export function calculateExpectedOutput(
  amountIn: bigint,
  reserveInput: bigint,
  reserveOutput: bigint
): bigint {
  if (reserveInput === BigInt(0)) return BigInt(0);
  return (amountIn * reserveOutput) / reserveInput;
}

/**
 * Calculate sqrt price limit based on direction
 * MIN_SQRT_PRICE + 1 for zeroForOne = true
 * MAX_SQRT_PRICE - 1 for zeroForOne = false
 */
export function getSqrtPriceLimitX96(zeroForOne: boolean): bigint {
  // TickMath.MIN_SQRT_PRICE = 4295128739
  // TickMath.MAX_SQRT_PRICE = 1461446703485210835077939753494
  if (zeroForOne) {
    return BigInt('4295128740'); // MIN_SQRT_PRICE + 1
  } else {
    return BigInt('1461446703485210835077939753493'); // MAX_SQRT_PRICE - 1
  }
}

/**
 * Encode swap call for SwapTest contract
 * Matches the signature used in PlexusYieldSwapTest.t.sol
 * 
 * @param poolKey - The pool configuration
 * @param amountSpecified - Negative for exact input, positive for exact output
 * @param zeroForOne - True if swapping token0 for token1
 * @param hookData - Optional hook data (default: empty bytes)
 * @returns Encoded function call data
 */
export function encodeSwapCall(
  poolKey: PoolKey,
  amountSpecified: bigint,
  zeroForOne: boolean,
  hookData: Hex = '0x' as Hex
): Hex {
  const sqrtPriceLimitX96 = getSqrtPriceLimitX96(zeroForOne);

  return encodeFunctionData({
    abi: SWAP_TEST_ABI,
    functionName: 'swap',
    args: [
      {
        currency0: poolKey.currency0,
        currency1: poolKey.currency1,
        fee: poolKey.fee as unknown as any,
        tickSpacing: poolKey.tickSpacing,
        hooks: poolKey.hooks,
      },
      {
        zeroForOne,
        amountSpecified,
        sqrtPriceLimitX96,
      },
      {
        takeClaims: false,
        settleUsingBurn: false,
      },
      hookData,
    ],
  });
}

export function getDeadline(seconds: number = 600): bigint {
  return BigInt(Math.floor(Date.now() / 1000) + seconds);
}