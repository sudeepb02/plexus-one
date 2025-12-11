import { 
    Address, 
    encodeFunctionData, 
    parseUnits, 
    formatUnits,
    encodeAbiParameters,
    encodePacked,
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
  
  // V4Router ABI
  export const V4_ROUTER_ABI = [
    {
      name: 'execute',
      type: 'function',
      inputs: [
        { name: 'commands', type: 'bytes' },
        { name: 'inputs', type: 'bytes[]' },
        { name: 'deadline', type: 'uint256' }
      ],
      outputs: [],
      stateMutability: 'payable'
    }
  ] as const;
  
  export interface PoolKey {
    currency0: Address;
    currency1: Address;
    fee: number;
    tickSpacing: number;
    hooks: Address;
  }
  
  // V4Router Actions
  export const V4_ACTIONS = {
    SWAP_EXACT_IN_SINGLE: 0x06,
    SETTLE_ALL: 0x0c,
    TAKE_ALL: 0x0d,
  } as const;
  
  // Universal Router Commands
  export const ROUTER_COMMANDS = {
    V4_SWAP: 0x10,
  } as const;
  
  export function buildPoolKey(): PoolKey {
    const mockUSDC = CONTRACTS.MOCK_USDC.toLowerCase();
    const yieldToken = CONTRACTS.YIELD_TOKEN.toLowerCase();
  
    const currency0 = mockUSDC < yieldToken ? CONTRACTS.MOCK_USDC : CONTRACTS.YIELD_TOKEN;
    const currency1 = mockUSDC < yieldToken ? CONTRACTS.YIELD_TOKEN : CONTRACTS.MOCK_USDC;
  
    return {
      currency0: currency0 as Address,
      currency1: currency1 as Address,
      fee: 500, // 0.05%
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
   * Encode SWAP_EXACT_IN_SINGLE params
   * Structure: (PoolKey, bool, uint128, uint128, bytes)
   */
  export function encodeSwapExactInSingleParams(
    poolKey: PoolKey,
    amountIn: bigint,
    minAmountOut: bigint,
    zeroForOne: boolean
  ): Hex {
    return encodeAbiParameters(
      [
        {
          type: 'tuple',
          components: [
            { name: 'currency0', type: 'address' },
            { name: 'currency1', type: 'address' },
            { name: 'fee', type: 'uint24' },
            { name: 'tickSpacing', type: 'int24' },
            { name: 'hooks', type: 'address' },
          ],
        },
        { type: 'bool' },
        { type: 'uint128' }, // Swap params MUST be uint128
        { type: 'uint128' }, // Swap params MUST be uint128
        { type: 'bytes' },
      ],
      [
        [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks] as any,
        zeroForOne,
        amountIn,
        minAmountOut,
        '0x' as Hex,
      ]
    );
  }
  
  /**
   * Encode complete swap with actions and params
   */
  export function encodeSwap(
    poolKey: PoolKey,
    amountIn: bigint,
    minAmountOut: bigint,
    zeroForOne: boolean
  ): { commands: Hex; inputs: Hex[] } {
    
    // 1. Encode Commands: 0x10 (V4_SWAP)
    const commands = `0x${ROUTER_COMMANDS.V4_SWAP.toString(16).padStart(2, '0')}` as Hex;
  
    // 2. Encode Actions: SWAP (0x06) -> SETTLE_ALL (0x0c) -> TAKE_ALL (0x0d)
    const actions = encodePacked(
      ['uint8', 'uint8', 'uint8'],
      [V4_ACTIONS.SWAP_EXACT_IN_SINGLE, V4_ACTIONS.SETTLE_ALL, V4_ACTIONS.TAKE_ALL]
    );
  
    // 3. Encode Action Inputs
    const inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
    const outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
  
    // Param 0: Swap Params (uint128 amounts)
    const param0 = encodeSwapExactInSingleParams(
      poolKey,
      amountIn,
      minAmountOut,
      zeroForOne
    );
  
    // Param 1: Settle Params (currency, maxAmount)
    // FIX: Settle params usually expect uint256 for the amount/maxAmount
    const param1 = encodeAbiParameters(
      [{ type: 'address' }, { type: 'uint256' }], 
      [inputCurrency, amountIn] // Using amountIn as max amount to settle
    );
  
    // Param 2: Take Params (currency, minAmount)
    // FIX: Take params usually expect uint256 for the amount
    const param2 = encodeAbiParameters(
      [{ type: 'address' }, { type: 'uint256' }], 
      [outputCurrency, minAmountOut]
    );
  
    const params = [param0, param1, param2];
  
    // Combine Actions + Params into the single input required for V4_SWAP command
    const encodedInput0 = encodeAbiParameters(
      [{ type: 'bytes' }, { type: 'bytes[]' }],
      [actions, params]
    );
  
    return {
      commands,
      inputs: [encodedInput0],
    };
  }
  
  export function encodeRouterExecute(
    commands: Hex,
    inputs: Hex[],
    deadline: bigint
  ): Hex {
    return encodeFunctionData({
      abi: V4_ROUTER_ABI,
      functionName: 'execute',
      args: [commands, inputs, deadline]
    });
  }
  
  export function getDeadline(seconds: number = 600): bigint {
    return BigInt(Math.floor(Date.now() / 1000) + seconds);
  }