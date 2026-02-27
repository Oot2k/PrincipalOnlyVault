# Edge Cases and Yield Manager Guidelines

This document outlines critical edge cases and provides guidance for the yield manager to handle exceptional scenarios.

## Bad Debt in Yield Source

Bad debt handling depends on the underlying yield source implementation:

- **Socialized losses** (e.g., Morpho): Losses are passed to users as the share price decreases
- **Non-socialized losses**: This indicates an issue with the underlying yield source requiring immediate emergency withdrawal

### Response to Bad Debt

1. Follow the underlying protocol's remediation instructions
2. Execute emergency withdrawal to realize losses and protect remaining principal

## Underlying Protocol Activates Governance Fees

Protocols that impose fees should generally not be used as yield sources. If such a protocol must be used, fee handling should be implemented at the wrapper level in the yield source contract, as fees break the ERC4626 standard (e.g., a specialized yield source implementation is required).

## Non-Standard ERC4626 Behavior

All non-standard ERC4626 behavior must be implemented at the yield source level using a custom yield source wrapper.

## Changing Yield Sources

When removing an old yield source, leftover balances may remain in the contract if the skip function is used. This creates phantom balance that is no longer tracked.

**Important:** Skip should only be used when:
- The underlying source has irrecoverably bad debt
- Withdrawal from the source is impossible

### Claiming Funds from Old Yield Sources

To claim funds from a previously configured yield source, the yield manager can execute an atomic transaction:

1. Set the yield source to the old claimable source
2. Emergency claim the funds
3. Revert the yield source back to the current value

This approach avoids unintended side effects.

## Security: Malicious Yield Source Risk

Exercise extreme caution when setting yield sources. A malicious yield source that reports the contract's balance as yield would allow the manager to drain the contract.

**Mitigation:** The `changeYieldSource` function can only be called by an admin to prevent unauthorized changes.

## Target Buffer BPS

The target buffer BPS should be set conservatively based on application requirements and average withdrawal size. A recommended default value is 50%.

For contracts used exclusively for short-term crypto prediction markets, 5-10% may be sufficient.

## Supported Tokens

The contract should only be used with standard ERC20 tokens as the underlying asset. 