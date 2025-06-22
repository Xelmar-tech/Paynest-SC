# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

PayNest is an Aragon OSx plugin ecosystem for payment infrastructure, transforming standalone payment contracts into modular Aragon plugins supporting streaming and scheduled payments with username-based addressing.

### Version Structure

The codebase maintains **dual-version architecture** with V1 (production-deployed) and V2 (enhanced) implementations:

**V1 (Legacy/Production)**
- `src/v1/` - Production contracts deployed on Base mainnet
- Simple username → address mapping (one-to-one)
- Single stream/schedule per user per type limitation
- Basic payment functionality with Aragon integration

**V2 (Enhanced/Current)**
- `src/v2/` - Enhanced architecture with controller/recipient separation
- Multiple payments per user support (unlimited streams/schedules)
- Smart account UX with separate control and payment addresses  
- Meta-transaction support (EIP-712 gasless operations)
- Flow-based streaming aligned with LlamaPay's natural design

### Core Components

**AddressRegistry** (`src/v2/AddressRegistry.sol`)
- Global username → address mapping with controller/recipient separation
- V2 supports smart account UX: signing account != payment recipient
- Enhanced username validation (3-20 chars, stricter V2 rules)
- Meta-transaction support for gasless operations

**PaymentsPlugin** (`src/v2/PaymentsPlugin.sol`)
- Aragon UUPS upgradeable plugin for DAO payment management
- Unlimited streams and schedules per user (removes V1 limitations)
- LlamaPay integration for streaming, native scheduling for recurring payments
- Permission-based access control with `MANAGER_PERMISSION_ID`

**PaymentsPluginSetup** (`src/v2/setup/PaymentsPluginSetup.sol`)
- Aragon plugin installation/upgrade management
- UUPS proxy deployment with proper permission configuration

### Key V2 Architectural Patterns

**Controller/Recipient Separation**
```solidity
struct UsernameData {
    address controller;     // Smart account that manages settings
    address recipient;      // Where payments are delivered  
    uint256 lastUpdateTime; // Audit trail
}
```

**Multiple Payment Support**
```solidity
// V2 allows unlimited payments per user
mapping(string => bytes32[]) userStreams;    // Alice can have N streams
mapping(string => bytes32[]) userSchedules; // Alice can have N schedules
```

## Essential Commands

### Build and Test

```bash
# Build contracts
forge build

# Run unit tests (fast, local only - 133 V2 tests)
make test

# Run fork tests (real Base mainnet integration - 28 V2 tests)
make test-fork

# Run invariant tests (property-based testing - 28 V2 tests)
FOUNDRY_INVARIANT_RUNS=10 forge test --match-contract ".*InvariantsV2"

# Generate test coverage report
make test-coverage
```

### Test Architecture Patterns

**V2 Test Structure**
- `test/v2/unit/` - Fast unit tests with mocks (133 tests)
- `test/v2/fork-tests/` - Real contract integration on Base mainnet (28 tests)
- `test/v2/invariant/` - Property-based testing with 33M+ function calls (28 tests)

**Testing Best Practices**
- V2 fork tests validate against live Base mainnet contracts
- Use `PaymentsForkBuilderV2` for fork test setup patterns
- Proxy pattern required: `ERC1967Proxy` for plugin initialization
- Real LlamaPay behavior differs from mocks (test both scenarios)

### Test Management with Bulloak

```bash
# Sync YAML test definitions to Solidity
make sync-tests

# Check if test files are out of sync
make check-tests

# Generate markdown test documentation  
make markdown-tests
```

### Deployment

```bash
# Simulate deployment
make predeploy

# Deploy to network (runs tests first)
make deploy

# Resume failed deployment
make resume
```

### Contract Verification

```bash
# Verify on Etherscan-compatible explorers
make verify-etherscan

# Verify on BlockScout
make verify-blockscout

# Verify on Sourcify
make verify-sourcify
```

## Development Workflow

### PayNest V2 Development

**Reference Implementation Patterns**
- `PaymentsPlugin.sol` → Reference for UUPS upgradeable plugin architecture
- `PaymentsPluginSetup.sol` → Reference for plugin setup and permission management
- Follow existing Aragon permission patterns with `auth()` modifiers
- Use `_msgSender()` instead of `msg.sender` for meta-transaction compatibility

**V2 Enhanced Features**
- Controller/recipient separation for smart account UX
- Multiple payment flows per user (unlimited streams/schedules)
- Enhanced username validation with V2 format rules
- Meta-transaction support (EIP-712) for gasless operations

### Testing Development Patterns

**Unit Testing**
- Use proper ERC1967Proxy pattern for plugin initialization
- Test both controller and recipient separation scenarios
- V2 username validation requires 3-20 characters, stricter rules

**Fork Testing** 
- Real Base mainnet integration with production contracts
- USDC approval patterns: check sufficient approval vs `type(uint256).max`
- LlamaPay stream lifecycle: cancelled streams revert on `withdrawable()` calls
- Flow rate parameters: use `uint216` for V2, rates typically `1e12` to `1e18` range

**Invariant Testing**
- Test V2 controller/recipient separation consistency  
- Verify username format validation across all operations
- System-wide integration between registry and plugin components

## Coding Style Guide

### Error Handling
- **ALWAYS use custom errors instead of require statements**
- Custom errors are more gas efficient and provide better error messages
- Example:
  ```solidity
  // ❌ NEVER use this
  require(amount > 0, "Amount must be positive");

  // ✅ ALWAYS use this  
  if (amount == 0) revert AmountMustBePositive();
  ```

### Meta-Transaction Support
- Use `_msgSender()` instead of `msg.sender` in V2 contracts
- PaymentsPlugin inherits Context through PluginUUPSUpgradeable

### Documentation
- **Provide verbose comments** for all functions and complex logic
- Use NatSpec comments for all public/external functions
- Explain the "why" not just the "what"
- Document all assumptions and edge cases

## Key Implementation Notes

### V2 Architecture Decisions

**Controller/Recipient Separation**
- Enables smart account users to sign with one address, receive payments at another
- Critical for UX: smart account + paymaster signing != payment destination
- Pattern: `controller` manages settings, `recipient` receives funds

**Multiple Payment Support**
- Removes artificial V1 limitation of one stream + one schedule per user
- Real organizations need: salary stream + equity stream + bonus schedules
- Uses array-based storage: `userStreams[username]` returns `bytes32[]`

**Flow-Based Streaming**
- Aligns with LlamaPay's natural design (no artificial end dates)
- V2 uses flow rates (`uint216 amountPerSec`) directly
- Simpler than V1's funding period calculations

### Testing Implementation Lessons

**Fork Testing Patterns**
- Use `PaymentsForkBuilderV2` for production-like DAO creation
- Real USDC doesn't use `type(uint256).max` approval patterns
- LlamaPay cancelled streams revert with "stream doesn't exist"
- Fork tests prove production readiness, unit tests provide fast feedback

**Invariant Testing Patterns**
- Target test contract with `targetContract(address(this))` pattern
- V2 invariants cover controller/recipient separation consistency
- Property-based testing validates mathematical correctness

### Real Contract Addresses (Base Mainnet)

```solidity
address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;
address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant ADDRESS_REGISTRY_V2 = 0x0a7DCbbc427a8f7c2078c618301B447cCF1B3Bc0;
```

## Project Structure Philosophy

### Contract Organization
- V1 contracts in `src/v1/` (legacy, production-deployed)
- V2 contracts in `src/v2/` (enhanced, current development)
- Interfaces organized by version: `src/v2/interfaces/`

### Test Organization  
- Mirror contract structure: `test/v1/` and `test/v2/`
- Separate unit, fork, and invariant testing directories
- Test builders provide reusable setup patterns

### V1 vs V2 Decision Framework
- V1 for production stability and backward compatibility
- V2 for new features requiring controller/recipient separation
- Migration path: users control when to move from V1 to V2

## Git Workflow

### Commit Messages
- Use conventional commits format: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`
- Examples:
  - `feat(v2): add controller/recipient separation to AddressRegistry`
  - `test(v2): implement comprehensive invariant tests for PaymentsPlugin`
  - `docs(specs): update V2 architecture documentation`

### Pre-commit Hook
- Automatically formats Solidity files with `forge fmt`
- Prevents CI formatting failures by ensuring consistent code style
- Processes commits that include `.sol` files only

## Key Dependencies

- **Aragon OSx**: Core DAO and plugin framework (`lib/osx/`)
- **OpenZeppelin Upgradeable**: UUPS proxy patterns (`lib/openzeppelin-contracts-upgradeable/`)
- **LlamaPay**: Streaming protocol integration (Base mainnet deployment)
- **Bulloak**: YAML → Solidity test conversion for structured testing