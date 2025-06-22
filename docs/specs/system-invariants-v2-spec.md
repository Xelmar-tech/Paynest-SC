# PayNest System Invariants v2.0 Specification

## Overview

This document defines **85 critical invariants** for PayNest v2.0 that must be validated through comprehensive property-based testing. The invariants cover the new controller/recipient separation architecture and multiple payment support while maintaining the security and correctness guarantees of the system.

## Critical Invariants (Priority 1)

These invariants are fundamental to system correctness and security in the v2.0 architecture:

### Address Registry v2.0 Controller/Recipient Separation (AR2-1 to AR2-8)

**AR2-1: Controller/Recipient Data Consistency**
```solidity
// Valid usernames have both controller and recipient set
usernames[username].controller != address(0) ⟺ 
    usernames[username].recipient != address(0) ∧
    usernames[username].lastUpdateTime > 0
```

**AR2-2: Controller Authorization Integrity**
```solidity
// Only controllers can update their username data
updateRecipient_success ∨ transferControl_success ⟹ 
    msg.sender == usernames[username].controller
```

**AR2-3: Recipient Resolution Consistency**
```solidity
// Recipient resolution returns current recipient
getUserAddress(username) == usernames[username].recipient ∧
getRecipient(username) == usernames[username].recipient
```

**AR2-4: Controller Uniqueness**
```solidity
// Each controller can control at most one username
∀u1, u2: u1 ≠ u2 ∧ usernames[u1].controller != address(0) ∧ usernames[u2].controller != address(0) ⟹ 
    usernames[u1].controller ≠ usernames[u2].controller
```

**AR2-5: Recipient Flexibility**
```solidity
// Multiple usernames can have the same recipient (many-to-one allowed)
usernames[u1].recipient == usernames[u2].recipient ∧ u1 ≠ u2 is allowed
```

**AR2-6: Zero Address Protection**
```solidity
// Zero addresses never appear in valid username data
usernames[username].controller != address(0) ⟹ 
    usernames[username].recipient != address(0)
```

**AR2-7: Timestamp Monotonicity**
```solidity
// Update timestamps are monotonically increasing
updateRecipient_success ∨ transferControl_success ⟹ 
    usernames[username].lastUpdateTime >= old_lastUpdateTime ∧
    usernames[username].lastUpdateTime <= block.timestamp
```

**AR2-8: Backward Compatibility**
```solidity
// Legacy getUserAddress function returns recipient
getUserAddress(username) == getRecipient(username)
```

### Multiple Payment Financial Integrity (PP2-1 to PP2-12)

**PP2-1: Stream ID Uniqueness**
```solidity
// Stream IDs are globally unique across all usernames
∀u1, u2, id: (u1 ≠ u2 ∧ streams[u1][id].active ∧ streams[u2][id].active) ⟹ false
```

**PP2-2: Schedule ID Uniqueness**
```solidity
// Schedule IDs are globally unique across all usernames
∀u1, u2, id: (u1 ≠ u2 ∧ schedules[u1][id].active ∧ schedules[u2][id].active) ⟹ false
```

**PP2-3: Active Stream Validity**
```solidity
// Active streams have valid flow rates and tokens
streams[username][streamId].active == true ⟹ 
    streams[username][streamId].token != address(0) ∧ 
    streams[username][streamId].amountPerSec > 0 ∧
    streams[username][streamId].startTime <= block.timestamp
```

**PP2-4: Stream-Recipient Consistency**
```solidity
// Active streams have recipients, inactive streams don't
streams[username][streamId].active == true ⟺ 
    streamRecipients[username][streamId] != address(0)
```

**PP2-5: Flow Rate Bounds**
```solidity
// Flow rates fit in LlamaPay's uint216 precision
streams[username][streamId].active == true ⟹ 
    streams[username][streamId].amountPerSec <= type(uint216).max
```

**PP2-6: Stream ID List Consistency**
```solidity
// User stream ID arrays contain only valid stream IDs
∀streamId ∈ userStreamIds[username]: 
    streams[username][streamId].token != address(0)
```

**PP2-7: Schedule Validity**
```solidity
// Active schedules have valid parameters
schedules[username][scheduleId].active == true ⟹ 
    schedules[username][scheduleId].token != address(0) ∧ 
    schedules[username][scheduleId].amount > 0 ∧
    schedules[username][scheduleId].firstPaymentDate > 0
```

**PP2-8: Schedule ID List Consistency**
```solidity
// User schedule ID arrays contain only valid schedule IDs
∀scheduleId ∈ userScheduleIds[username]: 
    schedules[username][scheduleId].token != address(0)
```

**PP2-9: Username Dependency for Active Payments**
```solidity
// Active payments require valid usernames with recipients
(streams[username][streamId].active ∨ schedules[username][scheduleId].active) ⟹ 
    registry.getRecipient(username) != address(0)
```

**PP2-10: Payment Count Bounds**
```solidity
// Reasonable limits on payments per user
userStreamIds[username].length <= MAX_STREAMS_PER_USER ∧
userScheduleIds[username].length <= MAX_SCHEDULES_PER_USER
```

**PP2-11: Stream Migration Consistency**
```solidity
// Stream recipients should match current username recipients (eventually)
// This invariant allows temporary mismatches during migration
streams[username][streamId].active == true ∧ 
migration_not_in_progress ⟹ 
    streamRecipients[username][streamId] == registry.getRecipient(username)
```

**PP2-12: LlamaPay Contract Mapping**
```solidity
// Token to LlamaPay mappings are valid when set
tokenToLlamaPay[token] != address(0) ⟹ 
    llamaPayFactory.getLlamaPayContractByToken(token) == tokenToLlamaPay[token]
```

## High Priority Invariants (Priority 2)

### Enhanced Username Validation (AR2-9 to AR2-12)

**AR2-9: Username Format Consistency with V1**
```solidity
// All claimed usernames still meet V1 format requirements
usernames[username].controller != address(0) ⟹ 
    bytes(username).length > 0 ∧ 
    bytes(username).length <= 32 ∧
    _isLetter(bytes(username)[0])
```

**AR2-10: Meta-Transaction Support**
```solidity
// Meta-transaction signatures are properly validated
claimUsernameWithSignature_success ⟹ 
    _validateSignature(username, recipient, controller, signature) == true ∧
    deadline >= block.timestamp
```

### Flow-Based Streaming Integrity (PP2-13 to PP2-22)

**PP2-13: Flow Rate Precision Accuracy**
```solidity
// Flow rate calculations maintain precision for target amounts
_calculateFlowRate(totalAmount, duration, token) * duration / 
    (10 ** (20 - IERC20WithDecimals(token).decimals())) ≈ totalAmount
    // Allow for reasonable rounding errors
```

**PP2-14: Indefinite Stream Consistency**
```solidity
// Flow-based streams don't have artificial end dates in metadata
streams[username][streamId].active == true ⟹ 
    streams[username][streamId].endDate == 0 ∨ 
    streams[username][streamId].endDate == type(uint40).max
```

**PP2-15: Stream State Transitions**
```solidity
// Stream state transitions are logical
pauseStream_success ⟹ streams[username][streamId].active == false ∧
resumeStream_success ⟹ streams[username][streamId].active == true ∧
cancelStream_success ⟹ streams[username][streamId].active == false ∧
    streams[username][streamId].token == address(0)
```

**PP2-16: LlamaPay Stream Synchronization**
```solidity
// Active PayNest streams have corresponding LlamaPay streams
streams[username][streamId].active == true ⟹ 
    ILlamaPay(tokenToLlamaPay[streams[username][streamId].token])
        .withdrawable(dao(), streamRecipients[username][streamId], 
                     streams[username][streamId].amountPerSec)
        .withdrawableAmount >= 0
```

**PP2-17: Flow Rate Update Efficiency**
```solidity
// Flow rate updates use modifyStream when possible
updateFlowRate_success ∧ recipient_unchanged ⟹ 
    llamaPay.modifyStream_called == true ∧
    llamaPay.cancelStream_called == false ∧
    llamaPay.createStream_called == false
```

**PP2-18: Multiple Token Support**
```solidity
// Users can have multiple streams with different tokens
∀t1, t2, s1, s2: t1 ≠ t2 ∧ s1 ≠ s2 ⟹ 
    (streams[username][s1].token == t1 ∧ streams[username][s2].token == t2) is allowed
```

**PP2-19: Concurrent Stream Management**
```solidity
// Multiple streams can be active simultaneously
count(streams[username][*].active == true) >= 0 ∧
count(streams[username][*].active == true) <= MAX_STREAMS_PER_USER
```

**PP2-20: Schedule Timing with Multiple Intervals**
```solidity
// Multiple schedules can have different intervals
∀s1, s2: s1 ≠ s2 ∧ schedules[username][s1].active ∧ schedules[username][s2].active ⟹ 
    schedules[username][s1].interval == schedules[username][s2].interval is allowed
```

**PP2-21: Payment Portfolio Consistency**
```solidity
// User payment portfolios are internally consistent
userStreamIds[username].length == count(streamId: streams[username][streamId].token != address(0)) ∧
userScheduleIds[username].length == count(scheduleId: schedules[username][scheduleId].token != address(0))
```

**PP2-22: Bulk Operation Atomicity**
```solidity
// Bulk operations either fully succeed or fully fail for safety
pauseAllUserStreams_success ⟹ 
    ∀streamId ∈ returned_pausedStreamIds: streams[username][streamId].active == false
```

### Enhanced Migration System (MG2-1 to MG2-8)

**MG2-1: Migration Authorization v2**
```solidity
// Only current username controllers can migrate payments
migrateStream_success ∨ migrateAllStreams_success ⟹ 
    msg.sender == registry.getController(username)
```

**MG2-2: Selective Migration Consistency**
```solidity
// Stream-specific migration only affects target stream
migrateStream(username, targetStreamId)_success ⟹ 
    ∀otherStreamId ≠ targetStreamId: 
        streamRecipients[username][otherStreamId] == old_streamRecipients[username][otherStreamId]
```

**MG2-3: Bulk Migration Completeness**
```solidity
// Bulk migration updates all specified streams
migrateAllStreams_success ⟹ 
    ∀streamId ∈ userStreamIds[username] where streams[username][streamId].active:
        streamRecipients[username][streamId] == registry.getRecipient(username)
```

**MG2-4: Token-Specific Migration Scope**
```solidity
// Token-specific migration only affects streams for that token
migrateStreamsForToken(username, targetToken)_success ⟹ 
    ∀streamId where streams[username][streamId].token == targetToken:
        streamRecipients[username][streamId] == registry.getRecipient(username) ∧
    ∀streamId where streams[username][streamId].token ≠ targetToken:
        streamRecipients[username][streamId] == old_streamRecipients[username][streamId]
```

**MG2-5: Migration Necessity Validation**
```solidity
// Migration only happens when actually needed
migrateStream_success ⟹ 
    old_streamRecipients[username][streamId] ≠ registry.getRecipient(username)
```

**MG2-6: LlamaPay Migration Efficiency**
```solidity
// Migration uses LlamaPay's modifyStream when possible
migrateStream_success ∧ same_flow_rate ⟹ 
    llamaPay.modifyStream_called == true ∧
    llamaPay.cancelStream_called == false ∧
    llamaPay.createStream_called == false
```

**MG2-7: Migration Preview Accuracy**
```solidity
// Migration previews accurately reflect required operations
getMigrationPreview(username).migrationRequired == true ⟹ 
    ∃streamId ∈ userStreamIds[username]:
        streamRecipients[username][streamId] ≠ registry.getRecipient(username)
```

**MG2-8: Migration State Consistency**
```solidity
// Successful migrations leave system in consistent state
migrateStream_success ⟹ 
    streams[username][streamId].active == old_active ∧
    streams[username][streamId].amountPerSec == old_amountPerSec ∧
    streamRecipients[username][streamId] == registry.getRecipient(username)
```

## Medium Priority Invariants (Priority 3)

### Cross-Contract Integration (CC2-1 to CC2-6)

**CC2-1: Registry-Plugin Consistency**
```solidity
// Plugin registry references are valid and consistent
plugin.registry() == expected_registry_address ∧
registry.getRecipient(username) != address(0) ⟹ 
    payment_operations_can_resolve_recipient
```

**CC2-2: Multi-DAO Registry Sharing**
```solidity
// All PayNest DAOs share the same registry instance
∀dao1, dao2 created by PayNestDAOFactory: 
    PaymentsPlugin(dao1.paymentsPlugin).registry() == 
    PaymentsPlugin(dao2.paymentsPlugin).registry()
```

**CC2-3: LlamaPay Factory Consistency**
```solidity
// All plugins use the same LlamaPay factory
∀plugin ∈ paynest_plugins: 
    plugin.llamaPayFactory() == canonical_llamapay_factory
```

**CC2-4: Permission System Integration**
```solidity
// Plugin permissions are correctly configured
dao.hasPermission(plugin, EXECUTE_PERMISSION_ID) == true ∧
dao.hasPermission(manager, plugin, MANAGER_PERMISSION_ID) == true
```

### State Atomicity v2 (SA2-1 to SA2-8)

**SA2-1: Stream Creation Atomicity v2**
```solidity
// Stream creation sets all related state atomically
createStream_success ⟹ 
    (streams[username][streamId].active == true ∧ 
     streamRecipients[username][streamId] == registry.getRecipient(username) ∧
     streamId ∈ userStreamIds[username] ∧
     tokenToLlamaPay[token] != address(0)) ∨ 
    transaction_reverted
```

**SA2-2: Stream Cancellation Cleanup v2**
```solidity
// Stream cancellation clears all related state atomically
cancelStream_success ⟹ 
    streams[username][streamId].active == false ∧ 
    streamRecipients[username][streamId] == address(0) ∧
    streams[username][streamId].token == address(0)
```

**SA2-3: Schedule Creation Atomicity**
```solidity
// Schedule creation sets all state consistently
createSchedule_success ⟹ 
    (schedules[username][scheduleId].active == true ∧ 
     scheduleId ∈ userScheduleIds[username]) ∨ 
    transaction_reverted
```

**SA2-4: Recipient Update Propagation**
```solidity
// Registry recipient updates don't automatically affect existing payments
registry.updateRecipient_success ⟹ 
    ∀streamId: streamRecipients[username][streamId] == old_streamRecipients[username][streamId]
    // Manual migration required
```

**SA2-5: Bulk Operation Consistency**
```solidity
// Bulk operations maintain consistent state across all affected payments
pauseAllUserStreams_success ⟹ 
    ∀streamId ∈ returned_streamIds: streams[username][streamId].active == false ∧
    ∀streamId ∉ returned_streamIds: streams[username][streamId].active == old_active[streamId]
```

### Financial Bounds v2 (FB2-1 to FB2-8)

**FB2-1: Aggregate Flow Rate Bounds**
```solidity
// Total flow rates per token remain reasonable
∀token: sum(streams[*][*].amountPerSec where streams[*][*].token == token) 
    <= reasonable_total_flow_rate_bound
```

**FB2-2: DAO Balance Adequacy**
```solidity
// DAO maintains sufficient balance for active obligations
∀token: 
    IERC20(token).balanceOf(dao()) + llamaPayBalance[dao()][token] >= 
    sum(streams[*][*].amountPerSec where streams[*][*].token == token) * minimum_funding_period
```

**FB2-3: Schedule Payment Bounds**
```solidity
// Schedule payments don't exceed reasonable limits
schedules[username][scheduleId].active == true ⟹ 
    schedules[username][scheduleId].amount <= max_single_payment_amount
```

**FB2-4: Payment Portfolio Value Bounds**
```solidity
// Individual user payment portfolios remain within reasonable bounds
estimated_monthly_value(userStreamIds[username] + userScheduleIds[username]) 
    <= max_user_portfolio_value
```

## Implementation Guidelines for V2.0 Testing

### Enhanced Testing Framework Setup

```solidity
contract PayNestV2Invariants is Test {
    // V2.0 Target contracts
    AddressRegistryV2 public registry;
    PaymentsPluginV2 public plugin;
    PayNestDAOFactory public factory;
    
    // External dependencies
    MockLlamaPayFactory public llamaPayFactory;
    MockERC20[] public tokens;
    MockDAO public dao;
    
    // V2.0 specific test state
    mapping(string => bytes32[]) public userStreamIds;
    mapping(string => bytes32[]) public userScheduleIds;
    mapping(bytes32 => address) public streamToRecipient;
    
    // Test actors with different roles
    address[] public controllers;
    address[] public recipients;
    address[] public managers;
    
    function setUp() public {
        // Initialize V2.0 contracts with controller/recipient separation
        // Set up multiple test actors for each role
        // Configure realistic bounds for multiple payment fuzzing
        // Prepare tokens with different decimal configurations
    }
}
```

### Critical V2.0 Invariant Tests

**Priority 1: Core V2.0 Architecture (Must implement first)**
- AR2-1 to AR2-8: Controller/recipient separation
- PP2-1 to PP2-12: Multiple payment financial integrity
- MG2-1 to MG2-8: Enhanced migration system

**Priority 2: Advanced V2.0 Features**
- PP2-13 to PP2-22: Flow-based streaming integrity
- AR2-9 to AR2-12: Enhanced username validation
- CC2-1 to CC2-6: Cross-contract integration

**Priority 3: Edge Cases and Performance**
- SA2-1 to SA2-8: State atomicity v2
- FB2-1 to FB2-8: Financial bounds v2

### V2.0 Specific Testing Strategies

1. **Multiple Payment Fuzzing**: Test users with 5-20 active payments in various combinations
2. **Controller/Recipient Separation**: Test all permutations of controller vs recipient operations
3. **Migration Stress Testing**: Test migration scenarios with complex payment portfolios
4. **Flow-Rate Precision**: Test flow rate calculations across different token decimals
5. **Bulk Operation Testing**: Test bulk operations with various success/failure combinations

### V2.0 Metrics and Coverage

- **Target**: 100% of Priority 1 V2.0 invariants tested
- **Goal**: 90% of Priority 2 V2.0 invariants tested  
- **Stretch**: 75% of Priority 3 V2.0 invariants tested

### V2.0 Implementation Notes

- Implement ghost variables to track aggregate payment state across multiple payments
- Use bounded fuzzing for payment portfolio sizes to ensure reasonable test execution times
- Create helper functions for complex invariant checks involving multiple payment relationships
- Implement custom handlers for V2.0 specific operations (migration, bulk operations)
- Use advanced actor management for controller/recipient separation testing scenarios

### V2.0 Invariant Testing Phases

**Phase 1: Core Architecture Validation**
- Controller/recipient separation integrity
- Multiple payment data structure consistency
- Basic flow-based streaming operations

**Phase 2: Advanced Feature Validation** 
- Complex migration scenarios
- Bulk operation atomicity
- Cross-contract integration patterns

**Phase 3: Performance and Edge Case Validation**
- Large payment portfolio handling
- Gas bounds and performance characteristics  
- Recovery and error handling scenarios

This specification provides a comprehensive roadmap for implementing invariant testing that validates the correctness, security, and performance of PayNest v2.0's enhanced architecture with controller/recipient separation and multiple payment support.