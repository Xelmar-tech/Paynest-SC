// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {IRegistry} from "./interfaces/IRegistry.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @title AddressRegistry V2.0
/// @notice Advanced username-to-address registry with controller/recipient separation for PayNest ecosystem
/// @dev Implements controller/recipient separation to solve smart account UX problems where payment controllers
///      and payment recipients must be different addresses. This enables smart account users to control their
///      PayNest username while receiving payments at external wallets (hardware wallets, exchange addresses, etc.)
/// @author PayNest Team
contract AddressRegistry is IRegistry, EIP712, Context {
    using ECDSA for bytes32;

    /// @notice Maps usernames to their complete data structure
    /// @dev Core storage mapping from username string to UsernameData struct
    mapping(string => IRegistry.UsernameData) public usernames;

    /// @notice Maps addresses to their nonces for meta-transaction replay protection
    /// @dev Used in EIP-712 signature verification to prevent replay attacks
    mapping(address => uint256) public nonces;

    /// @notice EIP-712 typehash for username claiming with signature
    /// @dev Used for meta-transaction support enabling gasless username registration
    bytes32 private constant CLAIM_USERNAME_TYPEHASH =
        keccak256("ClaimUsername(string username,address recipient,address controller,uint256 nonce,uint256 deadline)");

    /// @notice Custom errors for gas-efficient error handling
    /// @dev All errors are custom errors instead of require statements for gas efficiency

    /// @notice Thrown when attempting to register a username that is already taken
    error UsernameAlreadyTaken();

    /// @notice Thrown when username format validation fails
    error InvalidUsername();

    /// @notice Thrown when recipient address is zero address
    error InvalidRecipient();

    /// @notice Thrown when caller is not authorized to perform controller actions
    error UnauthorizedController();

    /// @notice Thrown when trying to access data for a non-existent username
    error UsernameNotFound();

    /// @notice Thrown when EIP-712 signature verification fails
    error InvalidSignature();

    /// @notice Thrown when signature has expired past its deadline
    error ExpiredSignature();

    /// @notice Thrown when new controller address is zero address
    error InvalidController();

    /// @notice Initialize the contract with EIP-712 domain
    /// @dev Sets up EIP-712 domain for meta-transaction support
    constructor() EIP712("PayNest AddressRegistry", "1") {}

    /// @notice Register username with caller as controller and specified recipient
    /// @param username Unique string identifier (3-20 characters, lowercase alphanumeric + underscore)
    /// @param recipient Address where payments will be delivered
    /// @dev Controller becomes msg.sender, validates username format and availability
    function claimUsername(string calldata username, address recipient) external override {
        _claimUsername(username, recipient, _msgSender());
    }

    /// @notice Register username with explicit controller specification (for smart account factories)
    /// @param username Unique string identifier
    /// @param recipient Payment delivery address
    /// @param controller Address that will control username settings
    /// @dev Allows factories to create usernames on behalf of smart accounts
    /// @dev Access control: Only the controller themselves can register with explicit controller
    function claimUsername(string calldata username, address recipient, address controller) external override {
        // Only allow the controller themselves to register with explicit controller
        // This prevents unauthorized parties from registering usernames on behalf of others
        if (_msgSender() != controller) {
            revert UnauthorizedController();
        }

        _claimUsername(username, recipient, controller);
    }

    /// @notice Update where payments are delivered without changing control
    /// @param username Target username to update
    /// @param newRecipient New payment delivery address
    /// @dev Only current controller can call this function
    function updateRecipient(string calldata username, address newRecipient) external override {
        IRegistry.UsernameData storage data = usernames[username];

        // Validate username exists
        if (data.controller == address(0)) {
            revert UsernameNotFound();
        }

        // Validate caller is controller
        if (data.controller != _msgSender()) {
            revert UnauthorizedController();
        }

        // Validate new recipient
        if (newRecipient == address(0)) {
            revert InvalidRecipient();
        }

        address oldRecipient = data.recipient;

        // Update recipient and timestamp
        data.recipient = newRecipient;
        data.lastUpdateTime = block.timestamp;

        emit RecipientUpdated(username, oldRecipient, newRecipient);
    }

    /// @notice Transfer username control to new address
    /// @param username Username to transfer
    /// @param newController New controlling address
    /// @dev Only current controller can call this function, maintains existing recipient
    function transferControl(string calldata username, address newController) external override {
        IRegistry.UsernameData storage data = usernames[username];

        // Validate username exists
        if (data.controller == address(0)) {
            revert UsernameNotFound();
        }

        // Validate caller is controller
        if (data.controller != _msgSender()) {
            revert UnauthorizedController();
        }

        // Validate new controller
        if (newController == address(0)) {
            revert InvalidController();
        }

        address oldController = data.controller;

        // Update controller and timestamp
        data.controller = newController;
        data.lastUpdateTime = block.timestamp;

        emit ControlTransferred(username, oldController, newController);
    }

    /// @notice Enable gasless username registration via meta-transactions
    /// @param username Unique string identifier
    /// @param recipient Payment delivery address
    /// @param controller Address that will control username settings
    /// @param deadline Signature expiration timestamp
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    /// @dev Uses EIP-712 for signature verification, includes nonce for replay protection
    function claimUsernameWithSignature(
        string calldata username,
        address recipient,
        address controller,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        // Check deadline first to save gas on expired signatures
        if (block.timestamp > deadline) {
            revert ExpiredSignature();
        }

        // Build EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_USERNAME_TYPEHASH, keccak256(bytes(username)), recipient, controller, nonces[controller], deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        // Verify signature
        address signer = hash.recover(v, r, s);
        if (signer != controller) {
            revert InvalidSignature();
        }

        // Increment nonce to prevent replay attacks
        nonces[controller]++;

        // Execute the username claim
        _claimUsername(username, recipient, controller);
    }

    /// @notice Get the controller address for a username
    /// @param username The username to query
    /// @return The controller address, or zero address if username doesn't exist
    function getController(string calldata username) external view override returns (address) {
        return usernames[username].controller;
    }

    /// @notice Get the recipient address for a username
    /// @param username The username to query
    /// @return The recipient address, or zero address if username doesn't exist
    function getRecipient(string calldata username) external view override returns (address) {
        return usernames[username].recipient;
    }

    /// @notice Get the last update timestamp for a username
    /// @param username The username to query
    /// @return The timestamp of the last update, or 0 if username doesn't exist
    function getLastUpdate(string calldata username) external view override returns (uint256) {
        return usernames[username].lastUpdateTime;
    }

    /// @notice Get complete username data
    /// @param username The username to query
    /// @return The complete UsernameData struct
    function getUsernameData(string calldata username) external view override returns (IRegistry.UsernameData memory) {
        return usernames[username];
    }

    /// @notice Backward compatibility with v1.0 integrations
    /// @param username The username to resolve
    /// @return The recipient address (payment destination), zero address if username doesn't exist
    /// @dev This maintains compatibility with existing PayNest integrations expecting v1.0 behavior
    function getUserAddress(string calldata username) external view override returns (address) {
        return usernames[username].recipient;
    }

    /// @notice Check if a username is available for registration
    /// @param username The username to check
    /// @return True if available, false if taken
    /// @dev Username is available if no controller is set (controller is zero address)
    function isUsernameAvailable(string calldata username) external view override returns (bool) {
        return usernames[username].controller == address(0);
    }

    /// @notice Internal function to handle username claiming logic
    /// @param username The username to claim
    /// @param recipient The payment recipient address
    /// @param controller The controller address
    /// @dev Centralizes validation and registration logic used by both public claim functions
    function _claimUsername(string calldata username, address recipient, address controller) internal {
        // Validate username format
        _validateUsername(username);

        // Validate recipient address
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        // Validate controller address
        if (controller == address(0)) {
            revert InvalidController();
        }

        // Check username availability
        if (usernames[username].controller != address(0)) {
            revert UsernameAlreadyTaken();
        }

        // Initialize username data
        usernames[username] =
            IRegistry.UsernameData({controller: controller, recipient: recipient, lastUpdateTime: block.timestamp});

        emit UsernameRegistered(username, controller, recipient);
    }

    /// @notice Validate username format according to PayNest V2 rules
    /// @param username The username to validate
    /// @dev Enhanced validation with stricter rules than V1:
    ///      - Length: 3-20 characters (vs 1-32 in V1)
    ///      - Characters: lowercase letters, numbers, underscore only
    ///      - Must start with letter, cannot end with underscore
    ///      - More restrictive for better UX and consistency
    function _validateUsername(string calldata username) internal pure {
        bytes memory usernameBytes = bytes(username);
        uint256 length = usernameBytes.length;

        // Check length constraints (3-20 characters)
        if (length < 3 || length > 20) {
            revert InvalidUsername();
        }

        // Check first character must be a lowercase letter
        bytes1 firstChar = usernameBytes[0];
        if (!(firstChar >= "a" && firstChar <= "z")) {
            revert InvalidUsername();
        }

        // Check last character cannot be underscore
        bytes1 lastChar = usernameBytes[length - 1];
        if (lastChar == "_") {
            revert InvalidUsername();
        }

        // Validate all characters are lowercase letters, numbers, or underscore
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = usernameBytes[i];
            bool isValidChar = (char >= "a" && char <= "z") || (char >= "0" && char <= "9") || char == "_";

            if (!isValidChar) {
                revert InvalidUsername();
            }
        }

        // Additional rule: no consecutive underscores for better readability
        for (uint256 i = 0; i < length - 1; i++) {
            if (usernameBytes[i] == "_" && usernameBytes[i + 1] == "_") {
                revert InvalidUsername();
            }
        }
    }
}
