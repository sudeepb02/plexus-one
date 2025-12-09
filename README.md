# Plexus One

Plexus One is a decentralized yield trading protocol built on **Uniswap V4**. It enables users to trade and speculate on the future yield of assets through a custom **Time-Decaying Automated Market Maker (AMM)**.

## Overview

Plexus One allows for the creation of markets where **Yield Tokens (YT)** are traded against **Underlying Tokens**. The protocol utilizes a custom Uniswap V4 Hook to enforce a specific pricing invariant that accounts for the time value of money.

As a market approaches maturity, the value of the Yield Token converges based on the accrued yield, while the AMM pricing curve automatically adjusts to reflect the diminishing time remaining for yield accumulation.

> **Note**: While markets have a fixed maturity date, **users are not locked in**. The AMM facilitates continuous trading, allowing users to close their positions (sell YT or remove liquidity) at any time before maturity at the prevailing market price.

## Core Components

### 1. Yield Token (YT)
The Yield Token represents a **claim on the total yield** (accrued + future) of an underlying asset.
- **Behavior**: It is an **accumulating asset**. Its intrinsic value grows as yield accrues.
- **Value**: `Intrinsic Value (Accrued Yield) + Time Value (Future Yield)`
- **Redemption**: Holders can burn YT to redeem the **Accrued Yield** (Intrinsic Value).
- **No Streaming**: Yield is not streamed. It is embedded in the token. To realize the yield, one must sell or redeem the token.

### 2. PlexusYieldHook (The AMM)
The core of the protocol is a Uniswap V4 Hook (`PlexusYieldHook.sol`) that implements a custom pricing curve. It acts as the primary market maker for YT.
- **Liquidity**: LPs provide Underlying Tokens
- **Mechanism**: Prices YT based on reserves and time to maturity.

## User Flows & Economics

To understand how value flows through Plexus One, let's look at two primary participants: **Alice (Yield Buyer)** and **Bob (Yield Seller)**.

### Scenario
- **Asset**: ETH
- **Maturity**: 1 Year from now
- **Current Implied Yield**: 5% APY
- **Price of YT**: ~0.05 ETH (per 1 YT)

### 1. Going Long (Alice)
Alice believes the actual yield on ETH will be **higher than 5%** over the next year.

1.  **Action**: Alice swaps **0.05 ETH** for **1.0 YT** on the AMM.
2.  **Money Flow**: Alice pays 0.05 ETH.
    - **Curve Price**: ~0.05 ETH (Time Value).
    - **Accrued Value**: 0 ETH (at start).
3.  **Holding**: Throughout the year, the Oracle updates the yield rate.
    - If the rate is 10%, the **Intrinsic Value** of YT grows faster.
    - Alice holds the token. She does not claim anything yet.
4.  **Outcome**:
    - By maturity, 1.0 YT has an Intrinsic Value of 0.10 ETH (if yield was 10%).
    - Alice burns 1.0 YT and receives 0.10 ETH.
    - **Profit**: 0.10 (Received) - 0.05 (Paid) = +0.05 ETH.

### 2. Going Short / LP (Bob)
Bob wants to earn a **fixed 5%** on his ETH, and he is willing to take the other side of Alice's trade.

1.  **Action**: Bob locks **0.1 ETH** as margin/collateral and mints **1.0 YT**.
2.  **Trade**: He sells the 1.0 YT to Alice for **0.05 ETH**.
3.  **Liability**: Bob is now "Short Yield". He owes the **Total Yield** (Accrued + Future) to the YT holder.
    - As yield accrues, the "Debt" of his vault increases.
    - `Debt = MintedAmount * (CurrentIndex - InitialIndex)`
4.  **Outcome**:
    - If yield is low (e.g., 2%), Bob's debt is only 0.02 ETH. He settles the vault, pays 0.02 ETH, and keeps the rest of his collateral. Net Profit: 0.05 (Premium) - 0.02 (Paid) = +0.03 ETH.
    - If yield is high (e.g., 10%), Bob's debt is 0.10 ETH. He must pay 0.10 ETH to close the vault. Net Loss: 0.05 - 0.10 = -0.05 ETH.

### Economic Balance
- **Longs**: Pay Fixed (Price of YT), Receive Floating (Intrinsic Value Growth).
- **Shorts**: Receive Fixed (Price of YT), Pay Floating (Debt Growth).
- **Hybrid Pricing**: To prevent arbitrage, the AMM charges buyers for the **Accrued Yield** on top of the **Curve Price**.
    - `Price = Curve Price (Time Value) + Accrued Yield (Intrinsic Value)`
    - This ensures that as maturity approaches (Time Value $\to$ 0), the token price converges to the Accrued Yield, not 0.

## Pricing Logic: The Power Invariant

To accurately model the decay of yield value over time, we use a **Power Invariant** instead of the standard Constant Product formula.

$$ (R_{YT})^t \times R_{Und} = k $$

Where:
- $R_{YT}$: Reserve of Yield Tokens.
- $R_{Und}$: Reserve of Underlying Tokens.
- $t$: Normalized Time to Maturity ($0 \le t \le 1$).
  - $t = \frac{\text{Maturity} - \text{Now}}{\text{Maturity} - \text{Start}}$

### Why this works
The spot price ($P$) derived from this invariant is:
$$ P = t \times \frac{R_{Und}}{R_{YT}} $$

- **Implied Rate**: $\frac{R_{Und}}{R_{YT}}$ represents the market's view of the annualized yield.
- **Time Decay**: The factor $t$ automatically scales the price down as maturity approaches.

## Settlement Mechanism

The system uses a **Redemption on Burn** model.

- **Accrual**: A global index tracks the cumulative yield per unit of notional.
- **Redemption**: Users burn YT to receive the accrued yield (`Amount * (Index - Initial)`).
- **Solvency**: Shorts are liquidated if their collateral falls below `Accrued Debt + Maintenance Margin`.

## Architecture

- **`src/PlexusYieldHook.sol`**: The Uniswap V4 Hook managing the pool state, swaps, and liquidity. Implements **Hybrid Pricing**.
- **`src/YieldToken.sol`**: The ERC20 token implementing the **accumulating yield** logic. It manages vaults (Shorts) and redemption (Longs).
- **`src/lib/YieldMath.sol`**: Library implementing the power invariant math using fixed-point arithmetic.

## Development

This project is built with [Foundry](https://getfoundry.sh/).

### Build

```shell
forge build
```

### Test

```shell
forge test
```