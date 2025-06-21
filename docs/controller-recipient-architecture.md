# PayNest Controller/Recipient Architecture Specification

## Overview

This document outlines the architectural enhancement to PayNest's username registry system to support **controller/recipient separation** and **single stream per token per user**. This addresses the fundamental limitation where smart account signers cannot set different recipient addresses for payments.

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

### Single Stream Per Token Per User Architecture

```solidity
// Enhanced storage for per-token streams
mapping(string => mapping(address => Stream)) public streams;
mapping(string => mapping(address => address)) public streamRecipients;

// Stream management functions updated
function createStream(string calldata username, address token, uint216 amount, uint40 endDate) external;
function editStream(string calldata username, address token, uint256 amount) external;
function getStream(string calldata username, address token) external view returns (Stream memory);
function getAllUserStreams(string calldata username) external view returns (address[] memory, Stream[] memory);
```

**Key Design Principles:**
- **One stream per token per user**: Alice can have USDC stream AND WETH stream (but not multiple USDC streams)
- **Clear token separation**: Each token type managed independently
- **Efficient stream editing**: Uses LlamaPay's native `modifyStream()` function
- **Maintains existing migration patterns**: Per stream migration logic preserved

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
    
    // Compatibility function
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

// Enhanced stream editing using LlamaPay's modifyStream
function editStream(string calldata username, address token, uint256 amount) 
    external auth(MANAGER_PERMISSION_ID) {
    
    if (amount == 0) revert InvalidAmount();
    
    Stream storage stream = streams[username][token];
    if (!stream.active) revert StreamNotActive();
    
    // Use stored recipient address (not current username resolution)
    address recipient = streamRecipients[username][token];
    address llamaPayContract = tokenToLlamaPay[token];
    
    // Calculate new amount per second
    uint256 remainingDuration = stream.endDate > block.timestamp ? 
        stream.endDate - block.timestamp : 0;
    uint216 newAmountPerSec = _calculateAmountPerSec(amount, remainingDuration, token);
    
    // Use LlamaPay's native modifyStream function
    Action[] memory actions = new Action[](1);
    actions[0].to = llamaPayContract;
    actions[0].value = 0;
    actions[0].data = abi.encodeCall(
        ILlamaPay.modifyStream,
        (recipient, stream.amount, recipient, newAmountPerSec)
    );
    
    // Execute via DAO
    DAO(payable(address(dao()))).execute(
        keccak256(abi.encodePacked("edit-stream-", username, "-", Strings.toHexString(token))), 
        actions, 
        0
    );
    
    // Update stream metadata
    stream.amount = newAmountPerSec;
    
    emit StreamUpdated(username, token, amount);
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

## Implementation Strategy

Since this is a virgin project with no production DAOs, we can implement the clean new architecture directly without backward compatibility concerns.

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
- Meta-transaction support

### 2. Single Stream Per Token Tests
- Per-token stream creation (one USDC stream, one WETH stream per user)
- Stream isolation (token A doesn't affect token B)
- Stream editing with LlamaPay's modifyStream function
- Migration with multiple token streams per user

### 3. Integration Tests
- End-to-end workflows with smart accounts
- Cross-chain recipient scenarios (preparation)
- Manual migration workflows
- Gas optimization verification

## Changes Summary

### New Architecture Features
- ✅ **Registry Interface**: Controller/recipient separation for smart account compatibility
- ✅ **Stream Storage**: Per-token streams using nested mapping structure  
- ✅ **Function Signatures**: Stream functions now include token parameter for clarity
- ✅ **Stream Editing**: Efficient `modifyStream()` using LlamaPay's native function
- ✅ **Gas Optimization**: Removed vestigial `previousAddress` field

## Version Impact Assessment

This represents a **MAJOR version bump** (v1.0.0 → v2.0.0) because:

1. **Breaking Interface Changes**: Stream functions now require token parameters
2. **Storage Layout Changes**: New nested mapping structure
3. **Behavioral Changes**: Username resolution now separates controller vs recipient
4. **New Functionality**: Stream editing and per-token stream management

### Implementation Path
1. **Update Contract Interfaces**: Implement new controller/recipient registry
2. **Update PaymentsPlugin**: Add per-token stream storage and modifyStream functionality
3. **Update Frontend Integration**: Handle new per-token streams interface
4. **Comprehensive Testing**: Test new architecture patterns

## Implementation Phases

### Phase 1: Core Registry Enhancement
- ✅ Controller/recipient separation
- ✅ Remove previousAddress field
- ✅ Meta-transaction support
- ✅ Clean new interface design

### Phase 2: Single Stream Per Token Support
- ✅ Per-token stream storage (one stream per token per user)
- ✅ Enhanced stream management functions with modifyStream
- ✅ Clean implementation without legacy concerns
- ✅ Comprehensive testing

### Phase 3: Enhanced Features & Polish
- ✅ Bulk migration functions
- ✅ Gas optimization
- ✅ Enhanced view functions
- ✅ Documentation updates

This architecture provides a robust foundation for PayNest's evolution while maintaining security and user experience standards.