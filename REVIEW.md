### Address Registry

The `AddressHistory` struct has a previous address field, which is not used in the current implementation. Do you have any plans to utilize this field in the future, or should it be removed to simplify the code?

A point to take note of is, using Privy to authenticate users, they use their embedded wallets to interact with the system. With the current approach that sets user address to the `msg.sender` address, we need to have the user be able to change their address in the registry to say; a custodial wallet address and the embedded wallet should simply be used to authenticate the user.

### PaymentsPlugin

The suggested changes to the `PaymentsPlugin` contract was to allow for a single username to have multiple payment streams/schedules. I doubt LlamaPay supports this, so won't we need to implement our own streaming logic?

Schedules doesn't lock tokens like streams do! Should we allow that? Since streams lock tokens.
