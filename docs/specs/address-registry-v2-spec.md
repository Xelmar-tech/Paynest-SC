# Address Registry v2.0 Specification

## Overview

The Address Registry v2.0 introduces **controller/recipient separation** to solve the fundamental smart account UX problem where payment controllers and payment recipients must be different addresses. This enables smart account users to control their PayNest username while receiving payments at external wallets (hardware wallets, exchange addresses, etc.).

## Core Problems Solved

### Smart Account Payment Routing
- **Problem**: Smart accounts with paymasters (wallet A) want payments delivered to exchange wallets (wallet B)
- **Solution**: Controller (wallet A) manages username, recipient (wallet B) receives payments
- **Impact**: Enables true blockchain-abstracted payment experiences

### Vestigial Data Removal
- **Problem**: `previousAddress` field stored but never used, costing ~20k gas per update
- **Solution**: Replace with `lastUpdateTime` for audit trails
- **Impact**: Significant gas savings for username updates

## Data Architecture

### Core Data Structure

```solidity
struct UsernameData {
    address controller;     // Smart account that manages username settings
    address recipient;      // Where payments are delivered
    uint256 lastUpdateTime; // Audit trail timestamp
}

mapping(string => UsernameData) public usernames;
```

### Key Design Decisions

**Controller Authority**: 
- Only the controller can update recipient address
- Only the controller can transfer username ownership
- Controller receives all username management permissions

**Recipient Flexibility**:
- Can be any valid Ethereum address
- Can be updated without losing payment history
- Independent of controller authorization patterns

**Audit Trail**:
- `lastUpdateTime` replaces unused `previousAddress`
- Enables temporal tracking of username changes
- Reduces storage costs while maintaining accountability

## Interface Specification

### Core Functions

#### Username Registration

```solidity
function claimUsername(string calldata username, address recipient) external
```
**Purpose**: Register username with caller as controller and specified recipient
**Parameters**:
- `username`: Unique string identifier (3-20 characters, alphanumeric + underscore)
- `recipient`: Address where payments will be delivered
**Behavior**:
- Controller becomes `msg.sender`
- Validates username format and availability
- Initializes `UsernameData` with controller, recipient, and current timestamp
- Emits `UsernameRegistered(username, controller, recipient)`
**Errors**:
- `UsernameAlreadyTaken()` if username exists
- `InvalidUsername()` if format validation fails
- `InvalidRecipient()` if recipient is zero address

#### Advanced Registration (Delegated Control)

```solidity
function claimUsername(string calldata username, address recipient, address controller) external
```
**Purpose**: Register username with explicit controller specification (for smart account factories)
**Parameters**:
- `username`: Unique string identifier
- `recipient`: Payment delivery address
- `controller`: Address that will control username settings
**Behavior**:
- Allows factories to create usernames on behalf of smart accounts
- Validates caller has appropriate permissions
- Sets up controller/recipient separation from creation
**Access Control**: Restricted to authorized factories or controllers themselves

#### Recipient Management

```solidity
function updateRecipient(string calldata username, address newRecipient) external
```
**Purpose**: Update where payments are delivered without changing control
**Parameters**:
- `username`: Target username to update
- `newRecipient`: New payment delivery address
**Behavior**:
- Validates caller is current controller
- Updates recipient address and timestamp
- Emits `RecipientUpdated(username, oldRecipient, newRecipient)`
**Errors**:
- `UnauthorizedController()` if caller is not controller
- `InvalidRecipient()` if new recipient is zero address
- `UsernameNotFound()` if username doesn't exist

#### Ownership Transfer

```solidity
function transferControl(string calldata username, address newController) external
```
**Purpose**: Transfer username control to new address
**Parameters**:
- `username`: Username to transfer
- `newController`: New controlling address
**Behavior**:
- Validates caller is current controller
- Updates controller address and timestamp
- Maintains existing recipient
- Emits `ControlTransferred(username, oldController, newController)`

### Access Functions

#### Individual Lookups

```solidity
function getController(string calldata username) external view returns (address)
function getRecipient(string calldata username) external view returns (address)
function getLastUpdate(string calldata username) external view returns (uint256)
```

#### Complete Data Retrieval

```solidity
function getUsernameData(string calldata username) external view returns (UsernameData memory)
```

#### Backward Compatibility

```solidity
function getUserAddress(string calldata username) external view returns (address)
```
**Purpose**: Maintain compatibility with v1.0 integrations
**Behavior**: Returns recipient address (the payment destination)

### Meta-Transaction Support

#### Smart Account Integration

```solidity
function claimUsernameWithSignature(
    string calldata username,
    address recipient,
    address controller,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
) external
```
**Purpose**: Enable gasless username registration via meta-transactions
**Parameters**: Standard EIP-712 signature parameters plus username data
**Behavior**: Verifies signature and executes registration on behalf of controller

## Business Logic Specifications

### Username Validation Rules

**Format Requirements**:
- Length: 3-20 characters
- Characters: lowercase letters, numbers, underscore only
- Pattern: Must start with letter, cannot end with underscore
- Reserved: Cannot match contract function names or keywords

**Availability Logic**:
- Username availability is permanent once claimed
- No expiration or reclamation mechanisms
- Case-insensitive uniqueness enforcement

### Controller Authorization Model

**Permission Scope**:
- Update recipient address
- Transfer control to new address
- Authorize payment operations (via external contracts)
- Access username metadata

**Meta-Transaction Handling**:
- Use `Context._msgSender()` for paymaster compatibility
- Support EIP-712 typed signatures for gasless operations
- Validate deadlines and nonce management

### Recipient Management Logic

**Address Validation**:
- Reject zero address as recipient
- Accept any other valid Ethereum address
- No smart contract detection or restrictions

**Update Mechanics**:
- Immediate effect on new payment creations
- Existing payments remain unaffected (require manual migration)
- Timestamp tracking for audit purposes

## Error Handling Specification

### Custom Errors

```solidity
error UsernameAlreadyTaken();
error InvalidUsername();
error InvalidRecipient();
error UnauthorizedController();
error UsernameNotFound();
error InvalidSignature();
error ExpiredSignature();
```

### Error Context Requirements

**Username Validation Errors**:
- Provide clear feedback on format violations
- Distinguish between taken and invalid usernames

**Authorization Errors**:
- Include attempted action in error context
- Reference current controller for debugging

**Signature Errors**:
- Validate EIP-712 compliance
- Check deadline expiration before signature verification

## Event Specification

### Core Events

```solidity
event UsernameRegistered(string indexed username, address indexed controller, address indexed recipient);
event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);
event ControlTransferred(string indexed username, address indexed oldController, address indexed newController);
```

### Event Design Principles

**Indexing Strategy**:
- Username always indexed for filtering
- Address changes indexed for tracking
- Maximum 3 indexed parameters per event

**Data Completeness**:
- Include both old and new values for updates
- Timestamp available via block metadata
- Enable complete audit trail reconstruction

## Security Specifications

### Access Control Model

**Controller Supremacy**:
- Only controller can modify username data
- No administrative override capabilities
- No emergency pause or recovery mechanisms

**Signature Verification**:
- EIP-712 compliant message hashing
- Nonce tracking to prevent replay attacks
- Deadline enforcement for signature freshness

### Attack Vector Mitigations

**Front-Running Protection**:
- Username claims are first-come-first-served
- No value-based prioritization mechanisms
- Deterministic transaction ordering

**Spam Prevention**:
- Username format restrictions limit namespace pollution
- No bulk registration interfaces
- Gas costs provide natural rate limiting

## Integration Specifications

### PaymentsPlugin Integration

**Recipient Resolution**:
- PaymentsPlugin calls `getRecipient(username)` for payment delivery
- No caching of recipient addresses in payment contracts
- Real-time resolution ensures current recipient receives payments

**Controller Validation**:
- Payment modifications validate against `getController(username)`
- Controller authorization required for payment management operations
- Separation enables different authorization patterns

### Factory Integration

**DAO Creation Workflow**:
- Factory can register usernames during DAO creation
- Smart account address becomes controller
- Initial recipient can be same as controller or different address

**Batch Operations**:
- Support bulk username registrations for organization setups
- Atomic failure prevents partial registration of username sets

## Gas Optimization Specifications

### Storage Efficiency

**Struct Packing**:
- `UsernameData` designed for single storage slot efficiency
- Address packing with timestamp optimization
- Minimal storage reads for common operations

**Operation Costs**:
- Username registration: ~45k gas (down from 65k)
- Recipient update: ~25k gas (down from 45k)
- Lookup operations: <5k gas each

### Batch Operation Support

**Multi-Username Operations**:
- Batch recipient updates for related usernames
- Bulk ownership transfers for organization restructuring
- Gas-efficient loops with early termination on failures

## Testing Requirements

### Unit Test Coverage

**Core Functionality**:
- Username registration with various parameters
- Recipient updates with authorization validation
- Control transfers with proper event emission
- Lookup functions with edge cases

**Error Conditions**:
- All custom error scenarios
- Boundary condition testing
- Invalid input handling

### Integration Test Requirements

**Smart Account Flows**:
- Meta-transaction username registration
- Paymaster interaction patterns
- Cross-contract recipient resolution

**Multi-Contract Scenarios**:
- Username registration followed by payment creation
- Recipient updates with active payments
- Control transfers during active payment flows

### Gas Benchmarking

**Performance Targets**:
- Registration operations <50k gas
- Update operations <30k gas
- Lookup operations <5k gas
- Batch operations with linear scaling

## Migration Strategy from v1.0

### Data Migration Process

**Automatic Conversion**:
- Existing usernames become controller=recipient=current address
- `lastUpdateTime` set to migration block timestamp
- Preserve all existing username-to-address mappings

**Manual Separation**:
- Controllers can call `updateRecipient()` post-migration
- No forced separation for users who don't need it
- Backward compatibility maintained for simple use cases

### Contract Upgrade Path

**Proxy Upgrade**:
- Implement upgradeable proxy pattern
- Preserve storage layout compatibility
- Add new fields in append-only fashion

**Event Continuity**:
- Emit migration events for audit trail
- Mark v1.0 events as legacy in indexing systems
- Provide mapping between old and new event formats

## Deployment Specifications

### Constructor Parameters

```solidity
constructor() {
    // No initialization parameters required
    // Stateless deployment for maximum compatibility
}
```

### Initial State

**Empty Registry**:
- No pre-registered usernames
- No administrative accounts
- Pure permissionless operation from deployment

### Network Compatibility

**EVM Compatibility**:
- Standard Solidity without assembly
- Compatible with all EVM-equivalent chains
- No chain-specific dependencies

**Gas Model Assumptions**:
- Optimized for post-London fork gas mechanics
- Compatible with Layer 2 scaling solutions
- Efficient under variable gas price conditions

This specification provides the complete behavioral and technical requirements for implementing the Address Registry v2.0 without including any implementation code, enabling parallel development while ensuring architectural consistency.