// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title IRegistry
/// @notice Interface for username-to-address registry with controller/recipient separation
/// @dev V2.0 interface supporting smart account UX with separate control and payment addresses
interface IRegistry {
    /// @notice Username data structure with controller/recipient separation
    struct UsernameData {
        address controller; // Smart account that manages username settings
        address recipient; // Where payments are delivered
        uint256 lastUpdateTime; // Audit trail timestamp
    }

    /// @notice Emitted when a username is registered
    /// @param username The username that was registered
    /// @param controller Address that controls the username
    /// @param recipient Address that receives payments
    event UsernameRegistered(string indexed username, address indexed controller, address indexed recipient);

    /// @notice Emitted when a username's recipient address is updated
    /// @param username The username whose recipient was updated
    /// @param oldRecipient The previous recipient address
    /// @param newRecipient The new recipient address
    event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);

    /// @notice Emitted when username control is transferred
    /// @param username The username whose control was transferred
    /// @param oldController The previous controller address
    /// @param newController The new controller address
    event ControlTransferred(string indexed username, address indexed oldController, address indexed newController);

    /// @notice Register username with caller as controller and specified recipient
    /// @param username Unique string identifier (3-20 characters, alphanumeric + underscore)
    /// @param recipient Address where payments will be delivered
    function claimUsername(string calldata username, address recipient) external;

    /// @notice Register username with explicit controller specification (for smart account factories)
    /// @param username Unique string identifier
    /// @param recipient Payment delivery address
    /// @param controller Address that will control username settings
    function claimUsername(string calldata username, address recipient, address controller) external;

    /// @notice Update where payments are delivered without changing control
    /// @param username Target username to update
    /// @param newRecipient New payment delivery address
    function updateRecipient(string calldata username, address newRecipient) external;

    /// @notice Transfer username control to new address
    /// @param username Username to transfer
    /// @param newController New controlling address
    function transferControl(string calldata username, address newController) external;

    /// @notice Enable gasless username registration via meta-transactions
    /// @param username Unique string identifier
    /// @param recipient Payment delivery address
    /// @param controller Address that will control username settings
    /// @param deadline Signature expiration timestamp
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function claimUsernameWithSignature(
        string calldata username,
        address recipient,
        address controller,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Get the controller address for a username
    /// @param username The username to query
    /// @return The controller address
    function getController(string calldata username) external view returns (address);

    /// @notice Get the recipient address for a username
    /// @param username The username to query
    /// @return The recipient address
    function getRecipient(string calldata username) external view returns (address);

    /// @notice Get the last update timestamp for a username
    /// @param username The username to query
    /// @return The timestamp of the last update
    function getLastUpdate(string calldata username) external view returns (uint256);

    /// @notice Get complete username data
    /// @param username The username to query
    /// @return The complete UsernameData struct
    function getUsernameData(string calldata username) external view returns (UsernameData memory);

    /// @notice Backward compatibility with v1.0 integrations
    /// @param username The username to resolve
    /// @return The recipient address (payment destination)
    function getUserAddress(string calldata username) external view returns (address);

    /// @notice Check if a username is available for registration
    /// @param username The username to check
    /// @return True if available, false if taken
    function isUsernameAvailable(string calldata username) external view returns (bool);
}
