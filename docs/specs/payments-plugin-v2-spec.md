# Payments Plugin v2.0 Specification

## Overview

The Payments Plugin v2.0 fundamentally transforms PayNest's payment architecture to support **multiple payments per user** and **flow-based streaming** that aligns with LlamaPay's natural design. This addresses the core limitations that prevented real-world organizational payment complexity and smart account user experiences.

## Core Problems Solved

### Multiple Payment Support
- **Problem**: V1.0 limited users to one stream and one schedule total
- **Solution**: Unlimited streams and schedules per user with unique identifiers
- **Impact**: Enables complex compensation packages (salary + equity + bonuses)

### Flow-Based Streaming Architecture
- **Problem**: V1.0 forced artificial end dates over LlamaPay's flow-rate design
- **Solution**: Embrace LlamaPay's natural indefinite streaming with flow rates
- **Impact**: Simpler mental model, gas savings, and stream continuity

### Efficient Stream Editing
- **Problem**: V1.0 used expensive cancel-and-recreate pattern
- **Solution**: Use LlamaPay's native `modifyStream` function
- **Impact**: ~100k gas savings per edit with stream continuity preservation

### Enhanced Migration for Multiple Payments
- **Problem**: V1.0 migration assumes single payment per user
- **Solution**: Granular per-payment migration with bulk options
- **Impact**: Flexible migration strategies for complex payment portfolios

## Data Architecture

### Stream Storage Structure

```solidity
struct Stream {
    address token;          // ERC20 token for payments
    uint216 amountPerSec;   // Flow rate in LlamaPay's 20-decimal precision
    bool active;            // Stream state (active/paused/cancelled)
    uint40 startTime;       // When flow began (for calculations)
}

// Multiple streams per user using unique identifiers
mapping(string => mapping(bytes32 => Stream)) public streams;
mapping(string => mapping(bytes32 => address)) public streamRecipients;
mapping(string => bytes32[]) public userStreamIds;
```

### Schedule Storage Structure

```solidity
struct Schedule {
    address token;              // ERC20 token for payments
    uint256 amount;             // Amount per interval
    IntervalType interval;      // Payment frequency
    bool isOneTime;             // One-time vs recurring
    bool active;                // Schedule state
    uint40 firstPaymentDate;    // Initial payment timestamp
    uint40 nextPayout;          // Next scheduled payment
}

mapping(string => mapping(bytes32 => Schedule)) public schedules;
mapping(string => bytes32[]) public userScheduleIds;
```

### Unique Identifier Generation

**Stream ID Generation**:
```solidity
bytes32 streamId = keccak256(abi.encodePacked(
    username,
    token,
    amountPerSec,
    block.timestamp,
    userStreamIds[username].length
));
```

**Schedule ID Generation**:
```solidity
bytes32 scheduleId = keccak256(abi.encodePacked(
    username,
    token,
    amount,
    interval,
    block.timestamp,
    userScheduleIds[username].length
));
```

## Interface Specification

### Enhanced Stream Management

#### Stream Creation (Flow-Based)

```solidity
function createStream(
    string calldata username,
    address token,
    uint216 amountPerSec
) external auth(MANAGER_PERMISSION_ID) returns (bytes32 streamId)
```
**Purpose**: Create indefinite flow rate stream without artificial end dates
**Parameters**:
- `username`: Target username for payment
- `token`: ERC20 token address
- `amountPerSec`: Flow rate in LlamaPay's 20-decimal precision
**Returns**: Unique stream identifier for future operations
**Behavior**:
- Resolve username to current recipient address via registry
- Generate unique stream ID using deterministic hash
- Create LlamaPay stream with pure flow rate (no funding calculations)
- Store stream metadata with current recipient
- Add stream ID to user's stream list
- Emit `StreamCreated` event with stream ID

#### Native Flow Rate Updates

```solidity
function updateFlowRate(
    string calldata username,
    bytes32 streamId,
    uint216 newAmountPerSec
) external auth(MANAGER_PERMISSION_ID)
```
**Purpose**: Efficiently update stream flow rate using LlamaPay's native capabilities
**Parameters**:
- `username`: Stream owner username
- `streamId`: Unique stream identifier
- `newAmountPerSec`: New flow rate in LlamaPay precision
**Behavior**:
- Validate stream exists and is active
- Retrieve current recipient and LlamaPay contract
- Use LlamaPay's `modifyStream` function for efficient update
- Update stream metadata with new flow rate
- Maintain stream continuity (no interruption)
- Emit `FlowRateUpdated` event

#### Stream State Management

```solidity
function pauseStream(
    string calldata username,
    bytes32 streamId
) external auth(MANAGER_PERMISSION_ID)

function resumeStream(
    string calldata username,
    bytes32 streamId
) external auth(MANAGER_PERMISSION_ID)

function cancelStream(
    string calldata username,
    bytes32 streamId
) external auth(MANAGER_PERMISSION_ID)
```
**Purpose**: Fine-grained stream lifecycle management
**Behavior**:
- **Pause**: Temporarily stop flow (set flow rate to 0, maintain metadata)
- **Resume**: Restore previous flow rate from metadata
- **Cancel**: Permanently terminate stream and clear metadata

### Enhanced Schedule Management

#### Multiple Schedule Creation

```solidity
function createSchedule(
    string calldata username,
    address token,
    uint256 amount,
    IntervalType interval,
    bool isOneTime,
    uint40 firstPaymentDate
) external auth(MANAGER_PERMISSION_ID) returns (bytes32 scheduleId)
```
**Purpose**: Create additional scheduled payments for users
**Parameters**: Standard schedule parameters plus timing configuration
**Returns**: Unique schedule identifier for management
**Behavior**:
- Generate unique schedule ID using deterministic hash
- Store schedule metadata with all parameters
- Add schedule ID to user's schedule list
- No immediate token movement (deferred to execution)
- Emit `ScheduleCreated` event with schedule ID

#### Schedule Modification

```solidity
function updateScheduleAmount(
    string calldata username,
    bytes32 scheduleId,
    uint256 newAmount
) external auth(MANAGER_PERMISSION_ID)

function updateScheduleInterval(
    string calldata username,
    bytes32 scheduleId,
    IntervalType newInterval
) external auth(MANAGER_PERMISSION_ID)

function cancelSchedule(
    string calldata username,
    bytes32 scheduleId
) external auth(MANAGER_PERMISSION_ID)
```

### Bulk Operations Support

#### User Payment Overview

```solidity
function getUserStreams(string calldata username)
    external view returns (
        bytes32[] memory streamIds,
        Stream[] memory streamData
    )

function getUserSchedules(string calldata username)
    external view returns (
        bytes32[] memory scheduleIds,
        Schedule[] memory scheduleData
    )

function getUserActivePayments(string calldata username)
    external view returns (
        bytes32[] memory activeStreamIds,
        bytes32[] memory activeScheduleIds,
        uint256 totalActiveStreams,
        uint256 totalActiveSchedules
    )
```

#### Bulk Management Operations

```solidity
function pauseAllUserStreams(string calldata username)
    external auth(MANAGER_PERMISSION_ID)
    returns (bytes32[] memory pausedStreamIds)

function resumeAllUserStreams(string calldata username)
    external auth(MANAGER_PERMISSION_ID)
    returns (bytes32[] memory resumedStreamIds)

function getUserPaymentSummary(string calldata username)
    external view returns (PaymentSummary memory)
```

**PaymentSummary Structure**:
```solidity
struct PaymentSummary {
    uint256 totalActiveStreams;
    uint256 totalActiveSchedules;
    address[] uniqueTokens;
    uint256[] monthlyStreamAmounts;  // Estimated monthly flow
    uint256[] pendingScheduleAmounts;
}
```

## Advanced Migration System

### Granular Stream Migration

```solidity
function migrateStream(
    string calldata username,
    bytes32 streamId
) external
```
**Purpose**: Migrate specific stream to current recipient address
**Access Control**: Only current username controller can call
**Behavior**:
- Validate caller is current username controller
- Check stream exists and migration is needed
- Retrieve current recipient from registry
- Use LlamaPay's `modifyStream` to update recipient efficiently
- Update `streamRecipients` mapping
- Emit `StreamMigrated` event with specific stream ID

### Bulk Migration Operations

```solidity
function migrateAllStreams(string calldata username) external
    returns (bytes32[] memory migratedStreamIds)

function migrateStreamsForToken(
    string calldata username,
    address token
) external returns (bytes32[] memory migratedStreamIds)

function migrateSelectedStreams(
    string calldata username,
    bytes32[] calldata streamIds
) external returns (bytes32[] memory migratedStreamIds)
```

**Migration Strategies**:
- **All Streams**: Migrate every active stream for username
- **Token-Specific**: Migrate only streams for specific token
- **Selective**: Migrate only specified stream IDs

### Migration Safety Mechanisms

```solidity
function getMigrationPreview(string calldata username)
    external view returns (MigrationPreview memory)
```

**MigrationPreview Structure**:
```solidity
struct MigrationPreview {
    address currentRecipient;
    bytes32[] streamsNeedingMigration;
    bytes32[] schedulesNeedingMigration;
    uint256 estimatedGasCost;
    bool migrationRequired;
}
```

## Flow-Based Architecture Implementation

### LlamaPay Integration Patterns

#### Stream Creation Without End Dates

```solidity
function _createLlamaPayStream(
    address token,
    address recipient,
    uint216 amountPerSec,
    bytes32 streamId
) internal
```
**Purpose**: Create LlamaPay stream with pure flow rate
**Behavior**:
- Get or deploy LlamaPay contract for token
- Calculate required funding for reasonable buffer period
- Execute DAO action for token approval
- Execute DAO action for LlamaPay stream creation
- No artificial end date calculations
- Store LlamaPay stream reference for future operations

#### Efficient Stream Modification

```solidity
function _modifyLlamaPayStream(
    address token,
    address currentRecipient,
    uint216 currentAmountPerSec,
    address newRecipient,
    uint216 newAmountPerSec
) internal
```
**Purpose**: Use LlamaPay's native modification for efficiency
**Behavior**:
- Prepare DAO action for LlamaPay `modifyStream` call
- Single transaction updates both recipient and flow rate
- Maintains stream continuity and accumulated balances
- ~100k gas savings vs cancel-and-recreate pattern

### Flow Rate Calculation Enhancements

```solidity
function _calculateFlowRate(
    uint256 totalAmount,
    uint256 durationInSeconds,
    address token
) internal view returns (uint216 amountPerSec)
```
**Purpose**: Convert amount/duration to LlamaPay flow rate
**Behavior**:
- Handle token decimal precision properly
- Convert to LlamaPay's 20-decimal standard
- Validate fits in uint216 bounds
- Provide accurate flow rate for indefinite streaming

### Funding Strategy for Indefinite Streams

```solidity
function _calculateRecommendedFunding(
    uint216 amountPerSec,
    address token
) internal view returns (uint256 recommendedAmount)
```
**Purpose**: Calculate sensible funding amounts for indefinite streams
**Behavior**:
- Default to 6-month funding buffer
- Consider token value and flow rate
- Provide recommendations for DAO treasury management
- Allow manual funding adjustments for long-term streams

## Business Logic Specifications

### Multiple Payment Validation

**Uniqueness Enforcement**:
- Stream IDs must be unique across all users and time
- Schedule IDs must be unique across all users and time
- No duplicate active payments with identical parameters

**Resource Limits**:
- Reasonable limits on payments per user (e.g., 50 streams, 20 schedules)
- Gas-bounded bulk operations
- Efficient pagination for large payment portfolios

### Flow Rate Management

**Flow Rate Bounds**:
- Minimum flow rate: 1 wei per second
- Maximum flow rate: uint216.max (LlamaPay constraint)
- Validation against token decimal precision

**Stream Lifecycle States**:
- **Active**: Normal flow operation
- **Paused**: Temporarily stopped (flow rate = 0, metadata preserved)
- **Cancelled**: Permanently terminated (metadata cleared)

### Schedule Enhancement Logic

**Interval Types Enhanced**:
```solidity
enum IntervalType {
    Daily,      // 24 hours
    Weekly,     // 7 days
    BiWeekly,   // 14 days
    Monthly,    // 30 days
    Quarterly,  // 90 days
    SemiAnnual, // 180 days
    Yearly      // 365 days
}
```

**Eager Payout Logic Enhanced**:
- Calculate all missed payment periods
- Support for partial period calculations
- Maximum catchup limits to prevent excessive gas costs
- Detailed event emission for each payment period covered

## Security Specifications

### Access Control Model

**Manager Permission Scope**:
- Create, modify, and cancel payments
- Pause and resume stream operations
- Bulk payment management operations
- Payment parameter modifications

**User Migration Rights**:
- Only username controller can initiate migrations
- No administrative override for migration operations
- Granular migration control (per-stream, per-token, or bulk)

### Financial Security Measures

**DAO Treasury Protection**:
- All payments sourced from DAO treasury only
- No direct token transfers from plugin contract
- DAO action validation for all fund movements
- Balance checks before payment operations

**Stream Integrity Validation**:
- Verify LlamaPay stream exists before operations
- Validate recipient addresses match current registry data
- Protect against double-spending in schedule payments
- Atomic operations for complex multi-step processes

### Input Validation Enhancements

**Username Validation**:
- Registry resolution required for all payment operations
- Handle registry resolution failures gracefully
- Cache recipient addresses only within transaction scope

**Payment Parameter Validation**:
- Token address validation (non-zero, contract existence)
- Amount bounds checking (positive, within reasonable limits)
- Flow rate precision validation for LlamaPay compatibility
- Interval validation for schedule timing logic

## Error Handling Specification

### Enhanced Custom Errors

```solidity
// Multiple payment errors
error MaximumStreamsPerUserExceeded();
error MaximumSchedulesPerUserExceeded();
error StreamIdNotFound();
error ScheduleIdNotFound();
error DuplicateStreamParameters();

// Flow-based streaming errors
error InvalidFlowRate();
error FlowRateExceedsMaximum();
error InsufficientFundingForFlowRate();
error LlamaPayStreamNotFound();

// Migration-specific errors
error MigrationNotRequired();
error UnauthorizedMigration();
error MigrationAlreadyInProgress();
error BulkMigrationPartialFailure();

// Enhanced validation errors
error RecipientResolutionFailed();
error TokenNotSupported();
error InsufficientDAOBalance();
error PaymentOperationFailed();
```

### Error Context and Recovery

**Detailed Error Information**:
- Include relevant identifiers (streamId, scheduleId) in errors
- Provide context for debugging (expected vs actual values)
- Clear error messages for frontend integration

**Graceful Degradation**:
- Partial success handling for bulk operations
- Recovery mechanisms for failed migration attempts
- Rollback protection for multi-step operations

## Event Specification

### Enhanced Payment Events

```solidity
// Stream lifecycle events
event StreamCreated(
    string indexed username,
    bytes32 indexed streamId,
    address indexed token,
    uint216 amountPerSec,
    address recipient
);

event FlowRateUpdated(
    string indexed username,
    bytes32 indexed streamId,
    uint216 oldAmountPerSec,
    uint216 newAmountPerSec
);

event StreamStateChanged(
    string indexed username,
    bytes32 indexed streamId,
    StreamState oldState,
    StreamState newState
);

// Schedule events with IDs
event ScheduleCreated(
    string indexed username,
    bytes32 indexed scheduleId,
    address indexed token,
    uint256 amount,
    IntervalType interval
);

event ScheduleExecuted(
    string indexed username,
    bytes32 indexed scheduleId,
    uint256 amount,
    uint256 periods,
    address recipient
);

// Migration events
event StreamMigrated(
    string indexed username,
    bytes32 indexed streamId,
    address indexed oldRecipient,
    address newRecipient
);

event BulkMigrationCompleted(
    string indexed username,
    bytes32[] streamIds,
    uint256 successfulMigrations,
    uint256 failedMigrations
);
```

### Event Design Principles

**Comprehensive Indexing**:
- Username always indexed for user-specific filtering
- Unique IDs indexed for payment-specific operations
- Token addresses indexed for token-specific queries

**Complete Data Capture**:
- Include both old and new values for update events
- Capture bulk operation results with success/failure counts
- Provide sufficient data for audit trail reconstruction

## Integration Specifications

### Registry Integration Enhancements

**Dynamic Recipient Resolution**:
- Resolve recipient at payment execution time
- No caching of recipient addresses in payment storage
- Real-time adaptation to registry updates

**Controller Validation**:
- Validate payment operations against registry controller
- Support for delegated payment management
- Consistent authorization patterns across operations

### LlamaPay Integration Optimizations

**Native Function Usage**:
- Use `modifyStream` instead of cancel-and-recreate
- Implement `createStreamWithReason` for metadata
- Leverage `withdrawable` for accurate balance queries

**Token Compatibility**:
- Support for any ERC20 token with LlamaPay deployment
- Automatic LlamaPay contract deployment when needed
- Efficient caching of token-to-LlamaPay mappings

### DAO Factory Integration

**Multi-Plugin Coordination**:
- Share registry instance across all PayNest DAOs
- Consistent plugin configuration parameters
- Standardized permission setup patterns

## Performance Specifications

### Gas Optimization Targets

**Core Operations**:
- Stream creation: <80k gas (down from 120k)
- Flow rate update: <40k gas (down from 140k)
- Schedule execution: <60k gas (similar to v1.0)
- Migration per stream: <50k gas (new operation)

**Bulk Operations**:
- Linear gas scaling for bulk operations
- Early termination on first failure (when appropriate)
- Efficient batch processing with reasonable limits

### Storage Efficiency

**Mapping Structure Optimization**:
- Nested mappings for O(1) access patterns
- Efficient packing of struct fields
- Minimal storage reads for common operations

**Memory Usage**:
- Efficient array handling for bulk operations
- Streaming processing for large payment portfolios
- Memory-conscious pagination for view functions

## Testing Requirements

### Core Functionality Testing

**Multiple Payment Scenarios**:
- Users with 10+ active streams in different tokens
- Complex schedule combinations (weekly + monthly + quarterly)
- Mixed stream and schedule portfolios
- Bulk operations with partial failures

**Flow-Based Streaming**:
- Indefinite stream creation and management
- Flow rate updates with precision validation
- Stream pause/resume cycles
- Long-running stream behavior validation

### Migration Testing

**Migration Scenarios**:
- Single stream migration after recipient change
- Bulk migration with mixed success/failure
- Token-specific migration strategies
- Migration of complex payment portfolios

**Edge Cases**:
- Migration during active stream payouts
- Multiple rapid recipient changes
- Migration with insufficient DAO balance
- Concurrent migration attempts

### Integration Testing

**Cross-Contract Workflows**:
- Registry recipient updates followed by migration
- DAO treasury management during payment operations
- LlamaPay integration with various token types
- Multi-DAO payment coordination

**Real-World Scenarios**:
- Organization with 20+ employees with complex compensation
- User switching from smart account to hardware wallet
- DAO treasury rebalancing during active payments
- Token upgrades affecting active streams

## Deployment Strategy

### Phased Rollout Plan

**Phase 1: Core Infrastructure**
- Deploy Address Registry v2.0 with controller/recipient separation
- Deploy Payments Plugin v2.0 with multiple payment support
- Comprehensive testing on testnet with realistic scenarios

**Phase 2: Migration Tooling**
- Build migration interfaces for v1.0 → v2.0 transitions
- Develop bulk operation management tools
- Create payment portfolio analytics and monitoring

**Phase 3: Production Deployment**
- Deploy on Base mainnet with full feature set
- Launch with comprehensive documentation and examples
- Provide migration assistance for early adopters

### Configuration Parameters

**Plugin Initialization**:
```solidity
struct InitializationParams {
    address managerAddress;         // Payment manager
    address registryAddress;        // Address registry v2.0
    address llamaPayFactory;        // LlamaPay factory
    uint256 maxStreamsPerUser;      // Resource limits
    uint256 maxSchedulesPerUser;    // Resource limits
    uint256 defaultFundingPeriod;   // Funding strategy
}
```

### Network Compatibility

**Multi-Chain Support**:
- Consistent deployment across Base and Base Sepolia
- Shared registry instances per network
- Network-specific LlamaPay factory integration

**Upgrade Strategy**:
- UUPS upgradeable pattern maintained
- Storage layout compatibility with expansion slots
- Backward compatibility for core interface functions

This specification provides the complete architectural and behavioral requirements for implementing the Payments Plugin v2.0, enabling true multiple payment support and flow-based streaming that aligns with organizational payment complexity while maintaining the security and efficiency standards established in v1.0.