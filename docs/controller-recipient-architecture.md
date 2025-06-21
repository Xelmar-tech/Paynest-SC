# PayNest Controller/Recipient Architecture Specification

## Overview

This document outlines the architectural enhancement to PayNest's username registry system to support **controller/recipient separation** and **multiple streams per user**. This addresses the fundamental limitation where smart account signers cannot set different recipient addresses for payments.

## Current Architecture Problems

### Problem 1: Sender == Recipient Assumption
- Current system assumes the smart account signer is also the payment recipient
- Breaks UX vision where users sign with one wallet but receive payments elsewhere
- Prevents cross-chain recipient addresses
- Forces recipient to be whoever currently owns the username

### Problem 2: Single Stream Per User Limitation
- Users can only have one active stream regardless of token type
- Prevents multi-token payroll (USDC salary + WETH equity)
- GitHub Issue #2 identifies this as blocking feature

### Problem 3: Vestigial Code
- `previousAddress` field is stored but never used in business logic
- Only tested to verify it exists, never used for functionality
- Wastes ~20k gas per username update

## Proposed Architecture

### Enhanced Username Registry

```solidity
struct UsernameData {
    address controller;     // Smart account that manages username
    address recipient;      // Where payments actually go  
    uint256 lastUpdateTime; // Remove unused previousAddress
}

mapping(string => UsernameData) public usernames;
mapping(address => string) public controllerToUsername;
```

**Key Changes:**
- **Controller**: Smart account that can update username settings
- **Recipient**: Address that receives payments (can be different from controller)
- **Eliminated**: `previousAddress` field (vestigial code)

### Multiple Streams Architecture

```solidity
// Enhanced storage for per-token streams
mapping(string => mapping(address => Stream)) public streams;
mapping(string => mapping(address => address)) public streamRecipients;

// Stream management functions updated
function createStream(string calldata username, address token, uint216 amount, uint40 endDate) external;
function getStream(string calldata username, address token) external view returns (Stream memory);
function getAllUserStreams(string calldata username) external view returns (address[] memory, Stream[] memory);
```

**Benefits:**
- Multiple streams per user (one per token type)
- Clear separation by token address
- Maintains existing migration patterns per stream

## Implementation Details

### 1. Registry Interface Changes

#### New Functions
```solidity
interface IAddressRegistry {
    // Updated core functions
    function claimUsername(string calldata username, address recipient) external;
    function updateRecipient(string calldata username, address newRecipient) external;
    function getController(string calldata username) external view returns (address);
    function getRecipient(string calldata username) external view returns (address);
    
    // Backward compatibility
    function getUserAddress(string calldata username) external view returns (address); // Returns recipient
    
    // Events
    event UsernameClaimedV2(string indexed username, address indexed controller, address indexed recipient);
    event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);
}
```

#### Authorization Model
```solidity
modifier onlyController(string calldata username) {
    if (_msgSender() != usernames[username].controller) revert UnauthorizedController();
    _;
}

function updateRecipient(string calldata username, address newRecipient) external onlyController(username) {
    address oldRecipient = usernames[username].recipient;
    usernames[username].recipient = newRecipient;
    usernames[username].lastUpdateTime = block.timestamp;
    
    emit RecipientUpdated(username, oldRecipient, newRecipient);
}
```

### 2. PaymentsPlugin Integration

#### Stream Management Updates
```solidity
// Updated stream creation
function createStream(string calldata username, address token, uint216 amount, uint40 endDate) 
    external auth(MANAGER_PERMISSION_ID) {
    
    if (streams[username][token].active) revert StreamAlreadyExists();
    
    address recipient = registry.getRecipient(username);
    if (recipient == address(0)) revert UsernameNotFound();
    
    // Create LlamaPay stream to recipient
    _createLlamaPayStream(token, recipient, amount, username);
    
    // Store stream metadata
    streams[username][token] = Stream({
        token: token,
        endDate: endDate,
        active: true,
        amount: amount,
        lastPayout: uint40(block.timestamp)
    });
    
    streamRecipients[username][token] = recipient;
}
```

#### Manual Migration (Existing System Enhanced)
```solidity
// Enhanced manual migration for multiple streams
function migrateStream(string calldata username, address token) external {
    address currentRecipient = registry.getRecipient(username);
    if (_msgSender() != registry.getController(username)) revert UnauthorizedMigration();
    
    address oldStreamRecipient = streamRecipients[username][token];
    if (oldStreamRecipient == currentRecipient) revert NoMigrationNeeded();
    
    _migrateStreamToNewAddress(username, token, oldStreamRecipient, currentRecipient);
    
    emit StreamMigrated(username, token, oldStreamRecipient, currentRecipient);
}

// Bulk migration for all streams of a user
function migrateAllStreams(string calldata username) external {
    if (_msgSender() != registry.getController(username)) revert UnauthorizedMigration();
    
    address currentRecipient = registry.getRecipient(username);
    // Iterate through all active streams and migrate each one
    // Implementation details depend on how we track user's active streams
}
```

### 3. Smart Account Integration

#### Meta-Transaction Support
```solidity
import "@openzeppelin/contracts/utils/Context.sol";

function claimUsername(string calldata username, address recipient) external {
    address controller = _msgSender(); // Handles meta-transactions properly
    _claimUsername(username, controller, recipient);
}

function claimUsername(string calldata username, address recipient, address controller) external {
    address actualController = controller == address(0) ? _msgSender() : controller;
    // Add authorization validation if controller != _msgSender()
    _claimUsername(username, actualController, recipient);
}
```

## Migration Strategy

### 1. Backward Compatibility

#### Existing Function Support
```solidity
// Keep existing interface working
function getUserAddress(string calldata username) external view returns (address) {
    return usernames[username].recipient; // Return recipient for payments
}

// Deprecated but functional
function updateUserAddress(string calldata username, address newAddress) external {
    // Map to new function
    updateRecipient(username, newAddress);
}
```

#### Data Migration
```solidity
struct LegacyAddressHistory {
    address currentAddress;
    address previousAddress; // Will be discarded
    uint256 lastChangeTime;
}

function migrateFromLegacy(string[] calldata usernames) external onlyOwner {
    for (uint i = 0; i < usernames.length; i++) {
        LegacyAddressHistory memory legacy = legacyUserAddresses[usernames[i]];
        
        usernames[usernames[i]] = UsernameData({
            controller: legacy.currentAddress,
            recipient: legacy.currentAddress,    // Default: controller == recipient
            lastUpdateTime: legacy.lastChangeTime
        });
    }
}
```

### 2. Stream Data Migration

#### Single Stream to Multi-Stream
```solidity
function migrateStreamsToMultiToken() external onlyOwner {
    // For each existing stream, move from:
    // streams[username] -> streams[username][stream.token]
    // This is a one-time upgrade operation
}
```

## Security Considerations

### 1. Authorization Model
- **Controller Authority**: Only controller can update recipient address
- **Migration Permissions**: Only controller can trigger manual migration
- **Manual Migration Safety**: Reuses existing migration logic (proven secure)

### 2. Recipient Validation
```solidity
function updateRecipient(string calldata username, address newRecipient) external onlyController(username) {
    if (newRecipient == address(0)) revert InvalidRecipient();
    // Additional validations as needed
    
    usernames[username].recipient = newRecipient;
}
```

### 3. Stream Migration Safety
- Migration reuses existing `_migrateStreamToNewAddress()` function
- Maintains all existing safety checks and fund protection
- Manual migration requires controller authorization

## Gas Impact Analysis

### Registry Operations
- **Username Claim**: +10k gas (additional recipient field)
- **Recipient Update**: -20k gas (remove previousAddress SSTORE)
- **Net Impact**: Roughly neutral

### Stream Operations  
- **Stream Creation**: +15k gas (additional token mapping)
- **Multiple Streams**: Linear increase per additional stream
- **Manual Migration**: Same gas as current system (~200k per stream)

### Migration Operations
- **Single Stream Migration**: Same as current (~200k gas)
- **Multiple Stream Migration**: 200k × number of streams

## Testing Strategy

### 1. Registry Tests
- Controller/recipient separation
- Authorization validation
- Backward compatibility
- Meta-transaction support

### 2. Multiple Stream Tests
- Per-token stream creation
- Stream isolation (token A doesn't affect token B)
- Bulk stream operations
- Migration with multiple streams

### 3. Integration Tests
- End-to-end workflows with smart accounts
- Cross-chain recipient scenarios (preparation)
- Manual migration workflows
- Gas optimization verification

## Breaking Changes Summary

### Major Breaking Changes
- ✅ **Registry Interface**: New controller/recipient separation
- ✅ **Stream Storage**: Single mapping → nested mapping
- ✅ **Function Signatures**: Stream functions now require token parameter

### Backward Compatibility Maintained
- ✅ **getUserAddress()**: Returns recipient address
- ✅ **Existing Streams**: Migration script handles data conversion
- ✅ **Plugin Interface**: Core payment flows remain similar

## Version Impact Assessment

This represents a **MAJOR version bump** (v1.0.0 → v2.0.0) because:

1. **Breaking Interface Changes**: Stream functions now require token parameters
2. **Storage Layout Changes**: Requires proxy upgrade for existing deployments  
3. **Behavioral Changes**: Username resolution now returns recipient vs controller
4. **Migration Required**: Existing deployments need data migration

### Upgrade Path
1. **Deploy New Implementation**: v2.0.0 contracts
2. **Run Migration Scripts**: Convert existing data to new format
3. **Update Frontend Integration**: Handle new multiple streams interface
4. **Deprecation Notice**: Announce timeline for v1.x support end

## Implementation Phases

### Phase 1: Core Registry Enhancement
- ✅ Controller/recipient separation
- ✅ Remove previousAddress field
- ✅ Meta-transaction support
- ✅ Backward compatibility layer

### Phase 2: Multiple Streams Support
- ✅ Per-token stream storage
- ✅ Enhanced stream management functions
- ✅ Migration script for existing streams
- ✅ Comprehensive testing

### Phase 3: Enhanced Features & Polish
- ✅ Bulk migration functions
- ✅ Gas optimization
- ✅ Enhanced view functions
- ✅ Documentation updates

This architecture provides a robust foundation for PayNest's evolution while maintaining security and user experience standards.