# Yield-Bearing Prediction Market

An ERC4626 vault designed to solve the yield distribution problem in prediction markets.

> **⚠️ WARNING: UNAUDITED CODE**  
> These contracts have **NOT been audited**. Do not use in production or with real funds. This is experimental code for research and educational purposes only.

## Overview

This design originated from auditing multiple prediction markets in collaboration with Sherlock DeFi, Bailsec Security, and independent security reviews, including two projects ranked among the top five in TVL and volume. The architecture fundamentally addresses issues found across these audits.

### The Problem

Most issues in prediction markets stem from accounting mismatches:

- **CTF (Conditional Token Framework) assumes a fixed 1:1 exchange rate**
- **Vaults issue shares that fluctuate in value**
- **This mismatch forces manual accounting for rounding errors and yield fluctuations**

Traditional prediction markets face a dilemma with yield-bearing collateral:
- Yield accrues to token holders, creating accounting complexity
- Market odds become distorted as collateral value changes
- Payouts don't match original bet amounts
- Protocol loses potential revenue from idle collateral

### The Solution: Wrapped Collateral Vault

**PrincipalOnlyVault** wraps yield-bearing tokens and returns a stable, non-value-increasing token. This removes the need to modify Polymarket contracts and isolates risk management to the wrapper vault.

**Enforced Invariants:**

1. **Exchange rate can never increase above 1:1** (but can decrease) → Prevents bank runs or accounting breaks if underlying protocols activate fees or incur losses
2. **Yield claims can never reduce principal below deposited collateral** → Prevents the protocol from withdrawing user principal
3. **Liquidity buffer is maintained** → Allows controlled exposure to underlying strategies and smoother withdrawals
4. **Losses, if they occur, are correctly passed to users** instead of breaking invariants

**Key Properties:**
- **Stable share price**: 1 share = 1 asset, always
- **Principal protection**: Users withdraw exactly what they deposited
- **Yield capture**: Protocol earns yield on idle collateral
- **ERC4626 compatible**: Standard vault interface

## How It Works in Prediction Markets

1. Users deposit USDC → receive poUSDC shares at 1:1
2. Protocol deploys idle USDC to DeFi (Morpho, Aave, Compound)
3. Users bet with poUSDC shares in prediction markets
4. Market resolution uses stable 1:1 value (no yield distortion)
5. Protocol claims accrued yield separately via `claimYield()`
6. Winners withdraw principal in poUSDC → redeem for original USDC

This keeps prediction market math simple while capturing yield on locked liquidity, solving the issues described in [this article](URL yet to be published).

## Architecture

```
┌─────────────────────────────────────────────┐
│           Users (Depositors)                │
│   Deposit USDC → Get poUSDC shares (1:1)    │
└───────────────┬─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│          PrincipalOnlyVault (ERC4626)        │
│  • Tracks principal deposited               │
│  • Keeps 5% buffer for withdrawals          │
│  • Share price locked at 1:1                │
└───────┬───────────────────┬─────────────────┘
        │                   │
        ▼                   ▼
┌───────────────┐   ┌──────────────────────┐
│  Idle Buffer  │   │   Yield Source       │
│   (~5% USDC)  │   │  (Morpho, Aave)      │
└───────────────┘   └──────────────────────┘
                            │
                            ▼ (Yield accrues)
                    ┌──────────────────┐
                    │     Treasury     │
                    │  (Protocol rev)  │
                    └──────────────────┘
```

## Contracts

- **`PrincipalOnlyVault.sol`** — Main ERC4626 vault with yield capture
- **`IPrincipalOnlyVault.sol`** — Interface with events and errors
- **`IYieldSource.sol`** — ERC4626-compatible yield strategy interface

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - Ethereum development toolkit

## Setup

1. **Install Foundry** (if not already installed):
```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Clone and install dependencies**:
```shell
git clone <repository-url>
cd PrincipalOnlyVault
forge install
```

This will install:
- OpenZeppelin Contracts (for ERC4626, ERC20, AccessControl)
- Forge Standard Library (for testing)

## Usage

### Build

Compile the contracts:
```shell
forge build
```

### Test

Run all tests:
```shell
forge test
```

Run tests with verbosity:
```shell
forge test -vvv
```

Run tests with gas report:
```shell
forge test --gas-report
```

### Format

Format all Solidity files:
```shell
forge fmt
```

### Clean

Remove build artifacts:
```shell
forge clean
```
## About

These contracts were developed by SCAS, a smart contract security and research firm focused on DeFi security audits and economic attack modeling.
We specialize in lending protocols, prediction markets, vault systems, and complex cross-protocol integrations.
