# PaymentsPlugin Test Tree

## Username Management

### claimUsername

✓ User can claim an unclaimed username
✓ User cannot claim an already claimed username
✓ Username can be claimed with empty string
✓ Event is emitted on successful claim

### updateUserAddress

✓ Owner can update their username's address
✓ Non-owner cannot update username's address
✓ Cannot update address for non-existent username
✓ Event is emitted on successful update
✓ Can update to same address (idempotent)

### getUserAddress

✓ Returns correct address for claimed username
✓ Returns zero address for unclaimed username

## Payment Schedule Management

### createSchedule

Happy Paths:
✓ Admin can create one-time payment schedule
✓ Admin can create recurring payment schedule
✓ Can create schedule with ETH as token
✓ Can create schedule with ERC20 as token
✓ Event is emitted with correct parameters
✓ Schedule is stored with correct parameters

Sad Paths:
✓ Non-admin cannot create schedule
✓ Cannot create schedule for non-existent username
✓ Cannot create schedule with zero amount
✓ Cannot create schedule when active schedule exists
✓ Cannot create one-time schedule with past date

### executePayment

Happy Paths:
✓ Can execute one-time payment on exact date
✓ Can execute recurring payment on exact date
✓ Can execute payment with ETH
✓ Can execute payment with ERC20
✓ Payment deactivates after one-time payment
✓ Recurring payment updates next payout date
✓ Event is emitted with correct parameters
✓ Tokens are transferred from DAO to recipient

Sad Paths:
✓ Non-admin cannot execute payment
✓ Cannot execute payment before due date
✓ Cannot execute payment for non-existent schedule
✓ Cannot execute payment for inactive schedule
✓ Cannot execute payment if DAO has insufficient balance
✓ Cannot execute payment if recipient address is zero
✓ Handles failed token transfers appropriately

## Stream Management

### createStream

Happy Paths:
✓ Admin can create stream with ETH
✓ Admin can create stream with ERC20
✓ Can create stream with future end date
✓ Event is emitted with correct parameters
✓ Stream is stored with correct parameters

Sad Paths:
✓ Non-admin cannot create stream
✓ Cannot create stream for non-existent username
✓ Cannot create stream with zero amount
✓ Cannot create stream when active stream exists
✓ Cannot create stream with end date <= current time

### executeStream

Happy Paths:
✓ Can execute stream payment
✓ Calculates correct pro-rata amount
✓ Updates lastPayout timestamp
✓ Handles ETH streams correctly
✓ Handles ERC20 streams correctly
✓ Deactivates stream after end date
✓ Event is emitted with correct parameters
✓ Tokens are transferred from DAO to recipient

Sad Paths:
✓ Non-admin cannot execute stream
✓ Cannot execute inactive stream
✓ Cannot execute stream for non-existent username
✓ Cannot execute if no time has passed since last payout
✓ Cannot execute if DAO has insufficient balance
✓ Cannot execute if recipient address is zero
✓ Handles failed token transfers appropriately

## Permission Management

### Permissions

✓ Only admin can create payments
✓ Only admin can execute payments
✓ DAO can execute actions through plugin
✓ Plugin permissions can be revoked
✓ Plugin permissions can be granted to new admin

## Edge Cases

### General

✓ Handles zero address token (ETH) correctly
✓ Handles non-contract token address
✓ Handles reentrant calls
✓ Handles large numbers without overflow
✓ Handles minimum payment intervals
✓ Handles maximum payment amounts
✓ Functions work across block number changes
✓ Functions work across timestamp changes

### Token Specific

✓ Handles tokens with no decimals
✓ Handles tokens with 18 decimals
✓ Handles non-compliant ERC20 tokens
✓ Handles tokens that revert on zero transfers
✓ Handles tokens that return false on failure
✓ Handles tokens that don't return bool
✓ Handles deflationary tokens

### State Management

✓ Contract state remains consistent after failed operations
✓ Multiple payments/streams can be managed simultaneously
✓ State changes are atomic
✓ Storage slots are used efficiently
