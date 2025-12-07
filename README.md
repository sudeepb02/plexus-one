# Plexus One

Plexus One is a decentralized yield trading protocol built on **Uniswap V4**. It enables users to trade and speculate on the future yield of assets through a custom **Time-Decaying Automated Market Maker (AMM)**.

## Overview

Plexus One allows for the creation of markets where **Yield Tokens (YT)** are traded against **Underlying Tokens**. The protocol utilizes a custom Uniswap V4 Hook to enforce a specific pricing invariant that accounts for the time value of money.

As a market approaches maturity, the value of the Yield Token converges based on the accrued yield, while the AMM pricing curve automatically adjusts to reflect the diminishing time remaining for yield accumulation.

## Core Components

### 1. YieldLockHook (The AMM)
The core of the protocol is a Uniswap V4 Hook that implements a custom pricing curve. Unlike standard Constant Product AMMs ($x \cdot y = k$), Plexus One uses a **Power Invariant**:

$$ (R_{YT})^t \times R_{Und} = k $$

Where:
- $R_{YT}$: Reserve of Yield Tokens
- $R_{Und}$: Reserve of Underlying Tokens
- $t$: Normalized time to maturity ($0 \le t \le 1$)

This invariant ensures that the price of Yield Tokens decays naturally over time as maturity approaches, preventing arbitrage drain and ensuring fair pricing.

### 2. Yield Token (YT)
An ERC20 token representing a claim on the variable yield of an underlying asset.
- **Maturity**: Each YT has a specific maturity date.
- **Settlement**: At maturity, YT can be redeemed for the accrued value.

### 3. YieldMath
A specialized library implementing the power invariant math using fixed-point arithmetic (`solmate`'s `FixedPointMathLib` and `LogExpMath`).

## Features

- **Uniswap V4 Integration**: Built as a Hook, leveraging the efficiency and liquidity of the V4 ecosystem.
- **ERC-6909 Support**: Uses the ERC-6909 standard for efficient liquidity provider (LP) token management within the hook.
- **Synthetic Settlement**: Supports both long (buying YT) and short (LPing/Selling YT) positions with automated settlement logic.

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
