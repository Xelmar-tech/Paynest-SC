// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title ILlamaPayFactory
/// @notice Interface for LlamaPay factory contract that deploys streaming contracts per token
interface ILlamaPayFactory {
    /// @notice Create a new LlamaPay contract for a token
    /// @param _token The token address to create a streaming contract for
    /// @return llamaPayContract The address of the deployed LlamaPay contract
    function createLlamaPayContract(address _token) external returns (address llamaPayContract);

    /// @notice Get the LlamaPay contract address for a token
    /// @param _token The token address to check
    /// @return predictedAddress The deterministic address where the contract would be deployed
    /// @return isDeployed Whether the contract is already deployed
    function getLlamaPayContractByToken(address _token)
        external
        view
        returns (address predictedAddress, bool isDeployed);

    /// @notice Get the total number of deployed LlamaPay contracts
    /// @return count The number of contracts
    function getLlamaPayContractCount() external view returns (uint256 count);

    /// @notice Get a LlamaPay contract by index
    /// @param index The index to retrieve
    /// @return contractAddress The contract address at that index
    function getLlamaPayContractByIndex(uint256 index) external view returns (address contractAddress);
}

/// @title ILlamaPay
/// @notice Interface for LlamaPay streaming payment contracts
interface ILlamaPay {
    /// @notice Create a stream to an address
    /// @param to The recipient address
    /// @param amountPerSec Amount per second in 20-decimal precision
    function createStream(address to, uint216 amountPerSec) external;

    /// @notice Create a stream with a reason
    /// @param to The recipient address
    /// @param amountPerSec Amount per second in 20-decimal precision
    /// @param reason Human-readable reason for the stream
    function createStreamWithReason(address to, uint216 amountPerSec, string calldata reason) external;

    /// @notice Cancel a stream
    /// @param to The recipient address
    /// @param amountPerSec Amount per second that was being streamed
    function cancelStream(address to, uint216 amountPerSec) external;

    /// @notice Pause a stream
    /// @param to The recipient address
    /// @param amountPerSec Amount per second that was being streamed
    function pauseStream(address to, uint216 amountPerSec) external;

    /// @notice Modify an existing stream
    /// @param oldTo Previous recipient address
    /// @param oldAmountPerSec Previous amount per second
    /// @param to New recipient address
    /// @param amountPerSec New amount per second
    function modifyStream(address oldTo, uint216 oldAmountPerSec, address to, uint216 amountPerSec) external;

    /// @notice Withdraw from a stream
    /// @param from The payer address
    /// @param to The recipient address
    /// @param amountPerSec Amount per second being streamed
    function withdraw(address from, address to, uint216 amountPerSec) external;

    /// @notice Get withdrawable amount from a stream
    /// @param from The payer address
    /// @param to The recipient address
    /// @param amountPerSec Amount per second being streamed
    /// @return withdrawableAmount Amount available to withdraw
    /// @return lastUpdate Timestamp of last update
    /// @return owed Amount owed if payer balance is insufficient
    function withdrawable(address from, address to, uint216 amountPerSec)
        external
        view
        returns (uint256 withdrawableAmount, uint256 lastUpdate, uint256 owed);

    /// @notice Deposit tokens to your LlamaPay balance
    /// @param amount Amount to deposit in native token decimals
    function deposit(uint256 amount) external;

    /// @notice Deposit tokens and create a stream in one transaction
    /// @param amountToDeposit Amount to deposit
    /// @param to Recipient address
    /// @param amountPerSec Amount per second for the stream
    function depositAndCreate(uint256 amountToDeposit, address to, uint216 amountPerSec) external;

    /// @notice Withdraw from your LlamaPay balance
    /// @param amount Amount to withdraw
    function withdrawPayer(uint256 amount) external;

    /// @notice Withdraw all of your LlamaPay balance
    function withdrawPayerAll() external;

    /// @notice Get a payer's balance (can be negative if in debt)
    /// @param payerAddress The payer to check
    /// @return balance The balance (positive) or debt (negative)
    function getPayerBalance(address payerAddress) external view returns (int256 balance);

    /// @notice Generate a stream ID
    /// @param from Payer address
    /// @param to Recipient address
    /// @param amountPerSec Amount per second
    /// @return streamId The keccak256 hash identifying the stream
    function getStreamId(address from, address to, uint216 amountPerSec) external pure returns (bytes32 streamId);

    /// @notice Get when a stream started
    /// @param streamId The stream ID
    /// @return startTime Timestamp when the stream started
    function streamToStart(bytes32 streamId) external view returns (uint256 startTime);

    /// @notice Get a payer's balance
    /// @param payer The payer address
    /// @return balance The balance in 20-decimal precision
    function balances(address payer) external view returns (uint256 balance);

    /// @notice Get the token contract for this LlamaPay instance
    /// @return tokenAddress The token contract address
    function token() external view returns (address tokenAddress);

    /// @notice Get the decimals divisor for this token
    /// @return divisor The divisor to convert between native and 20-decimal precision
    function DECIMALS_DIVISOR() external view returns (uint256 divisor);
}

/// @title IERC20WithDecimals
/// @notice Extended ERC20 interface that includes decimals function
interface IERC20WithDecimals {
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}
