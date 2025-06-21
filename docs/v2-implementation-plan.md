# PayNest V2.0 Implementation Plan

## Overview

This document outlines the step-by-step implementation plan for PayNest V2.0, introducing controller/recipient separation and multiple payment support. The plan focuses on the sequence of actions and validation gates, with implementation details found in the V2 specifications.

## Phase 1: Preserve V1 as Legacy

### Step 1: Restructure Source Code
- Move all current contracts from `src/` to `src/v1/`
- Rename contracts: `AddressRegistry` → `AddressRegistryV1`, `PaymentsPlugin` → `PaymentsPluginV1`
- Update all internal imports and references
- Move interfaces to `src/v1/interfaces/`

### Step 2: Restructure Tests
- Move all current tests from `test/` to `test/v1/`
- Update all test imports to reference V1 contracts
- Ensure test structure mirrors source structure

### Step 3: Verify V1 Preservation
- Run all V1 tests: `forge test --match-path "./test/v1/*.sol"`
- **Gate**: All 213 V1 tests must pass
- **Gate**: V1 contracts must compile without errors
- **Gate**: Git history preserved for all files

## Phase 2: Create V2 Foundation

### Step 4: Create V2 Source Structure
```
src/
├── v1/                    # Legacy contracts (preserved)
└── v2/                    # New V2 contracts  
    ├── AddressRegistry.sol
    ├── PaymentsPlugin.sol
    ├── PaymentsPluginSetup.sol
    └── interfaces/
        ├── IRegistry.sol
        └── IPayments.sol
```

### Step 5: Implement V2 Interfaces
- Create `src/v2/interfaces/IRegistry.sol` following address-registry-v2-spec.md
- Create `src/v2/interfaces/IPayments.sol` following payments-plugin-v2-spec.md

### Step 6: Verify Interface Design
- **Gate**: Interfaces must compile successfully
- **Gate**: Interface functions match V2 specifications exactly
- **Gate**: Events match V2 specifications exactly

## Phase 3: Implement V2 Contracts

### Step 7: Implement AddressRegistry V2
- Create `src/v2/AddressRegistry.sol` implementing `IRegistry`
- Follow controller/recipient separation architecture from address-registry-v2-spec.md
- Remove `previousAddress` field completely
- Implement all specified functions and error handling

### Step 8: Implement PaymentsPlugin V2
- Create `src/v2/PaymentsPlugin.sol` implementing `IPayments`
- Follow multiple payment architecture from payments-plugin-v2-spec.md
- Implement flow-based streaming (no artificial end dates)
- Implement unique ID system for streams and schedules

### Step 9: Implement PaymentsPluginSetup V2
- Create `src/v2/PaymentsPluginSetup.sol` for Aragon plugin deployment
- Follow Aragon OSx patterns from V1 but adapt for V2 architecture

### Step 10: Verify V2 Implementation
- **Gate**: All V2 contracts must compile
- **Gate**: V2 contracts must implement their interfaces completely
- **Gate**: No unused variables or vestigial code

## Phase 4: Create V2 Test Infrastructure

### Step 11: Create V2 Test Structure
```
test/
├── v1/                    # Legacy tests (preserved)
└── v2/                    # New V2 tests
    ├── unit/
    ├── fork/
    ├── invariant/
    └── builders/
```

### Step 12: Implement V2 Test Builders
- Create test builders for V2 architecture patterns
- Focus on controller/recipient separation scenarios
- Focus on multiple payment scenarios
- Focus on migration testing scenarios

### Step 13: Write Core V2 Tests
- **Preserve V1 Test Coverage**: Port all V1 test scenarios to V2 contracts
- **Add Controller/Recipient Tests**: New functionality for separation architecture
- **Add Multiple Payment Tests**: New functionality for unlimited streams/schedules
- **Add Flow-Based Streaming Tests**: New functionality for LlamaPay alignment
- **Add Migration Tests**: New functionality for enhanced migration system

### Step 14: Verify V2 Test Foundation
- **Gate**: All V2 unit tests must pass
- **Gate**: V1 test coverage preserved in V2 (all 213 scenarios)
- **Gate**: New V2 functionality fully tested
- **Gate**: Combined test count significantly higher than V1 (target: 300+ tests)
- **Gate**: V1 regression tests still pass (213/213)

## Phase 5: Comprehensive V2 Testing

### Step 15: Implement Integration Tests
- **Port V1 Integration Tests**: Ensure all V1 integration scenarios work in V2
- **Add V2 Cross-Contract Tests**: Controller/recipient interaction patterns
- **Add Complex Payment Scenarios**: Multiple streams + schedules combinations
- **Add Smart Account Workflows**: Real-world organizational payment flows

### Step 16: Implement Fork Tests  
- **Port V1 Fork Tests**: Ensure all V1 fork scenarios work in V2
- **Add V2 LlamaPay Integration**: Flow-rate efficiency and modifyStream usage
- **Add Migration Fork Tests**: Migration with live contract scenarios
- **Add Multi-Payment Fork Tests**: Complex payment portfolios on live networks

### Step 17: Implement Invariant Tests
- **Port V1 Invariants**: Ensure all V1 system properties hold in V2
- **Add V2 Invariants**: Follow system-invariants-v2-spec.md
- **Priority 1**: Critical security/correctness invariants  
- **Priority 2**: Important edge cases and performance invariants

### Step 18: Performance and Gas Testing
- Compare V1 vs V2 gas costs
- Validate gas optimization targets from specifications
- **Target**: Stream creation <80k gas (vs 120k in V1)
- **Target**: Flow rate update <40k gas (vs 140k in V1)
- **Target**: Recipient update <25k gas (vs 45k in V1)

### Step 19: Final Testing Gate
- **Gate**: All V2 tests pass (unit + integration + fork + invariant)
- **Gate**: V1 regression tests still pass (213/213)
- **Gate**: V1 test coverage completely preserved in V2
- **Gate**: V2 test count exceeds V1 (300+ tests total)
- **Gate**: Gas optimization targets met
- **Gate**: No unused variables or dead code

## Phase 6: Canonicalize V2

### Step 20: Make V2 Canonical
- Move V2 contracts from `src/v2/` to `src/`
- Move V2 interfaces from `src/v2/interfaces/` to `src/interfaces/`
- Move V2 tests from `test/v2/` to `test/`
- Keep V1 as legacy in `src/v1/` and `test/v1/`
- Update all documentation to reference canonical V2

### Step 21: Deploy V2 Contracts
- Deploy AddressRegistry V2 as canonical registry
- Deploy PaymentsPluginSetup V2 as canonical plugin setup
- Verify all deployments on target networks

### Step 22: Final Verification
- **Gate**: All canonical V2 tests pass
- **Gate**: V1 legacy tests still pass
- **Gate**: Contracts deployed and verified
- **Gate**: Documentation updated to V2

## Success Criteria

### Architecture Validation
✅ Controller/recipient separation working  
✅ Multiple payments per user working  
✅ Flow-based streaming working  
✅ Enhanced migration working  

### Code Quality
✅ No unused variables or vestigial code  
✅ All functions serve active business logic  
✅ Comprehensive error handling  
✅ Gas optimization targets met  

### Testing Completeness
✅ 100% specification coverage  
✅ V1 regression protection  
✅ Real-world scenario testing  
✅ Security invariant validation  

### Deployment Readiness
✅ Contracts deployed and verified  
✅ Documentation updated  
✅ Migration path documented  
✅ Rollback plan available  

## Timeline Estimate

- **Phase 1**: Preserve V1 (2-3 days)
- **Phase 2**: V2 Foundation (2-3 days)  
- **Phase 3**: V2 Implementation (1 week)
- **Phase 4**: V2 Test Infrastructure (3-4 days)
- **Phase 5**: Comprehensive Testing (1 week)
- **Phase 6**: Canonicalize V2 (2-3 days)

**Total: ~3 weeks**

## Key Benefits

✅ **Safety**: V1 preserved as working reference  
✅ **Quality**: Clear gates prevent low-quality progression  
✅ **Efficiency**: Focus on architecture, not implementation details  
✅ **Rollback**: Can revert to V1 if critical issues found  
✅ **Clean**: New deployment addresses without upgrade complexity