// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IOTC} from "./interfaces/IOTC.sol";
import {OTCConstants} from "./libraries/OTCConstants.sol";

/**
 * @title OTC Contract
 * @notice Proof of Capital OTC contract for managing token swaps with capital backing
 * @dev This contract allows locking tokens with guaranteed buyback under preset conditions
 *
 * Key features:
 * - Supports ETH or ERC20 as input token
 * - ERC20 as output token
 * - Multiple supply stages
 * - Time-locked phases
 * - Client approval system for farm account proposals
 * - Buyback mechanism at fixed price
 */
contract OTC is IOTC, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Contract state variables
    address public immutable override INPUT_TOKEN;
    address public immutable override OUTPUT_TOKEN;
    address public immutable override ADMIN_ADDRESS;
    address public immutable override CLIENT_ADDRESS;

    uint256 public immutable override BUYBACK_PRICE;
    uint256 public immutable override MIN_INPUT_AMOUNT;
    uint256 public immutable override MIN_OUTPUT_AMOUNT;

    bool public immutable override IS_SUPPLY;

    uint64 public override supplyLockEndTime;
    uint64 public override totalLockEndTime;
    uint64 public override proposedTime;
    uint8 public override supplyCount;
    uint8 public override currentSupplyIndex;
    uint8 public override currentState;

    mapping(uint8 => Supply) public override supplies;
    FarmWithdrawData public override withdrawData;

    /**
     * @notice Constructor to initialize the OTC contract
     * @param _inputToken Address of input token (address(0) for ETH)
     * @param _outputToken Address of output token
     * @param _admin Admin address
     * @param _client Client address
     * @param _supplies Array of supply structs
     * @param _buybackPrice Price for buyback (in NOMINATOR units)
     * @param _minOutputAmount Minimum output token amount
     * @param _minInputAmount Minimum input token amount
     * @param _isSupply True if this is a supply-side contract
     */
    constructor(
        address _inputToken,
        address _outputToken,
        address _admin,
        address _client,
        Supply[] memory _supplies,
        uint256 _buybackPrice,
        uint256 _minOutputAmount,
        uint256 _minInputAmount,
        bool _isSupply
    ) {
        require(_outputToken != address(0), IOTC.ZeroAddress());
        require(_admin != address(0), IOTC.ZeroAddress());
        require(_client != address(0), IOTC.ZeroAddress());
        require(_admin != _client, IOTC.SameAddress());
        require(_inputToken == address(0) || _inputToken != _outputToken, IOTC.SameTokens());
        require(_buybackPrice > 0, IOTC.InvalidBuybackPrice());
        require((!_isSupply || _supplies.length != 0) && (_isSupply || _supplies.length == 0), IOTC.InvalidSupplyCount());


        INPUT_TOKEN = _inputToken;
        OUTPUT_TOKEN = _outputToken;
        ADMIN_ADDRESS = _admin;
        CLIENT_ADDRESS = _client;
        BUYBACK_PRICE = _buybackPrice;
        MIN_OUTPUT_AMOUNT = _minOutputAmount;
        MIN_INPUT_AMOUNT = _minInputAmount;
        IS_SUPPLY = _isSupply;
        currentState = OTCConstants.STATE_FUNDING;



        uint256 outputSum = 0;
        uint256 inputSum = 0;

        for (uint8 i = 0; i < _supplies.length; i++) {
            require(_supplies[i].input > 0, IOTC.InvalidSupplyData());
            require(_supplies[i].output > 0, IOTC.InvalidSupplyData());
            supplies[i] = _supplies[i];
            supplyCount++;
            outputSum += _supplies[i].output;
            inputSum += _supplies[i].input;
        }

        supplyLockEndTime = uint64(block.timestamp) + OTCConstants.INITIAL_LOCK_PERIOD;

        require(!IS_SUPPLY || outputSum >= _minOutputAmount, IOTC.OutputSumTooLow());
        require(!IS_SUPPLY || inputSum >= _minInputAmount, IOTC.InputSumTooLow());
    }

    // Modifiers
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyClient() {
        _onlyClient();
        _;
    }

    modifier inState(uint8 requiredState) {
        _inState(requiredState);
        _;
    }

    // Internal modifier logic functions
    function _onlyAdmin() internal view {
        require(msg.sender == ADMIN_ADDRESS, IOTC.OnlyAdmin());
    }

    function _onlyClient() internal view {
        require(msg.sender == CLIENT_ADDRESS, IOTC.OnlyClient());
    }

    function _inState(uint8 requiredState) internal view {
        require(currentState == requiredState, IOTC.InvalidState(currentState, requiredState));
    }

    /**
     * @notice Deposit ETH as input
     * @dev Automatically checks if minimum amount is reached and transitions state
     */
    function depositEth() external payable override nonReentrant inState(OTCConstants.STATE_FUNDING) {
        require(IS_SUPPLY, IOTC.InvalidState(currentState, OTCConstants.STATE_FUNDING));
        require(INPUT_TOKEN == address(0), IOTC.InputTokenIsToken());

        emit DepositedInput(msg.sender, msg.value);

        // Check if minimum reached and transition state
        _checkAndTransitionInputState(address(this).balance);
    }

    /**
     * @notice Deposit ERC20 token as input
     * @param amount Amount of tokens to deposit
     * @dev Automatically checks if minimum amount is reached and transitions state
     */
    function depositToken(uint256 amount) external override nonReentrant inState(OTCConstants.STATE_FUNDING) {
        require(IS_SUPPLY, IOTC.InvalidState(currentState, OTCConstants.STATE_FUNDING));
        require(INPUT_TOKEN != address(0), IOTC.InputTokenIsEth());

        // Transfer tokens from sender
        IERC20(INPUT_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        // Get current balance
        uint256 currentBalance = IERC20(INPUT_TOKEN).balanceOf(address(this));

        emit DepositedInput(msg.sender, amount);

        // Check if minimum reached and transition state
        _checkAndTransitionInputState(currentBalance);
    }

    /**
     * @notice Deposit output token
     * @param amount Amount of output tokens to deposit
     * @dev Automatically checks if minimum amount is reached and transitions state
     */
    function depositOutput(uint256 amount) external override nonReentrant inState(OTCConstants.STATE_FUNDING) {
        require(!IS_SUPPLY, IOTC.InvalidState(currentState, OTCConstants.STATE_FUNDING));

        IERC20(OUTPUT_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = IERC20(OUTPUT_TOKEN).balanceOf(address(this));

        emit DepositedOutput(msg.sender, amount);

        if (balanceAfter >= MIN_OUTPUT_AMOUNT) {
            _changeState(OTCConstants.STATE_SUPPLY_PROVIDED);
            totalLockEndTime = uint64(block.timestamp) + OTCConstants.TOTAL_LOCK_PERIOD;
            emit OutputChecked(balanceAfter);
        }
    }

    /**
     * @notice Withdraw ETH by client after lock period
     * @param amount Amount of ETH to withdraw
     */
    function withdrawEth(uint256 amount) external override onlyClient nonReentrant {
        require(block.timestamp > supplyLockEndTime, IOTC.SupplyLockActive());
        require(INPUT_TOKEN == address(0), IOTC.InputTokenIsToken());
        require(amount > 0, IOTC.InvalidAmount());
        require(amount <= address(this).balance, IOTC.InsufficientBalance());

        emit Withdrawn(CLIENT_ADDRESS, amount);

        (bool success,) = CLIENT_ADDRESS.call{value: amount}("");
        require(success, IOTC.EthTransferFailed());
    }

    /**
     * @notice Withdraw input tokens by client after lock period
     * @param amount Amount to withdraw
     */
    function withdrawInput(uint256 amount) external override onlyClient nonReentrant {
        require(block.timestamp > supplyLockEndTime, IOTC.SupplyLockActive());
        require(INPUT_TOKEN != address(0), IOTC.InputTokenIsEth());

        emit InputWithdrawn(CLIENT_ADDRESS, amount);

        IERC20(INPUT_TOKEN).safeTransfer(CLIENT_ADDRESS, amount);
    }

    /**
     * @notice Withdraw output tokens by client after all lock periods
     * @param amount Amount to withdraw
     */
    function withdrawOutput(uint256 amount) external override onlyClient nonReentrant {
        require(block.timestamp > supplyLockEndTime, IOTC.SupplyLockActive());
        require(block.timestamp > totalLockEndTime, IOTC.TotalLockActive());

        _changeState(OTCConstants.STATE_CANCELED);

        emit OutputWithdrawn(CLIENT_ADDRESS, amount);

        IERC20(OUTPUT_TOKEN).safeTransfer(CLIENT_ADDRESS, amount);
    }

    /**
     * @notice Admin supplies the next tranche of output tokens to the contract
     */
    function supplyOutput() external override onlyAdmin nonReentrant {
        require(
            currentState == OTCConstants.STATE_SUPPLY_IN_PROGRESS,
            IOTC.InvalidState(currentState, OTCConstants.STATE_SUPPLY_IN_PROGRESS)
        );

        Supply memory currentSupply = supplies[currentSupplyIndex];

        // Transfer output tokens from admin
        IERC20(OUTPUT_TOKEN).safeTransferFrom(msg.sender, address(this), currentSupply.output);

        currentSupplyIndex++;

        // Transfer input tokens/ETH to admin
        if (INPUT_TOKEN == address(0)) {
            (bool success,) = ADMIN_ADDRESS.call{value: currentSupply.input}("");
            require(success, IOTC.EthTransferFailed());
        } else {
            IERC20(INPUT_TOKEN).safeTransfer(ADMIN_ADDRESS, currentSupply.input);
        }

        emit SupplyProcessed(currentSupplyIndex - 1, currentSupply.input, currentSupply.output);

        if (currentSupplyIndex == supplyCount) {
            _changeState(OTCConstants.STATE_SUPPLY_PROVIDED);
            totalLockEndTime = uint64(block.timestamp) + OTCConstants.TOTAL_LOCK_PERIOD;
        }
    }

    /**
     * @notice Admin proposes a farm account for token deployment
     * @param _withdrawData Farm account data including address and call data
     */
    function proposeFarmAccount(FarmWithdrawData calldata _withdrawData)
        external
        override
        onlyAdmin
        inState(OTCConstants.STATE_SUPPLY_PROVIDED)
        nonReentrant
    {
        withdrawData = _withdrawData;
        proposedTime = uint64(block.timestamp);

        _changeState(OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER);

        emit FarmAccountProposed(_withdrawData.farmAccount, proposedTime);
    }

    /**
     * @notice Client votes YES on the farm account proposal
     */
    function voteYes() external override onlyClient nonReentrant {
        require(
            currentState == OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER
                || currentState == OTCConstants.STATE_CLIENT_REJECTED,
            IOTC.InvalidState(currentState, OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER)
        );

        _changeState(OTCConstants.STATE_CLIENT_ACCEPTED);
        emit ClientVoted(true);
    }

    /**
     * @notice Client votes NO on the farm account proposal
     */
    function voteNo() external override onlyClient nonReentrant {
        require(
            currentState == OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER,
            IOTC.InvalidState(currentState, OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER)
        );

        _changeState(OTCConstants.STATE_CLIENT_REJECTED);
        emit ClientVoted(false);
    }

    /**
     * @notice Admin sends output tokens to the approved farm account
     */
    function sendToFarm() external override onlyAdmin inState(OTCConstants.STATE_CLIENT_ACCEPTED) nonReentrant {
        IERC20(OUTPUT_TOKEN).safeTransfer(withdrawData.farmAccount, MIN_OUTPUT_AMOUNT);

        emit TokensSentToFarm(withdrawData.farmAccount, MIN_OUTPUT_AMOUNT);

        if (withdrawData.sendData.length > 0) {
            (bool success,) = withdrawData.farmAccount.call(withdrawData.sendData);
            require(success, IOTC.FarmCallFailed());
        }
    }

    /**
     * @notice Admin executes buyback with input tokens
     * @param amount Amount of input tokens to use for buyback
     */
    function buybackWithToken(uint256 amount) external override onlyAdmin nonReentrant {
        require(INPUT_TOKEN != address(0), IOTC.InputTokenIsEth());
        require(
            currentState == OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER
                || currentState == OTCConstants.STATE_CLIENT_REJECTED || currentState == OTCConstants.STATE_CANCELED,
            IOTC.InvalidState(currentState, OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER)
        );
        require(
            block.timestamp > proposedTime + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD, IOTC.ProposeLockActive()
        );

        uint256 outputAmount = (amount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        require(outputAmount <= IERC20(OUTPUT_TOKEN).balanceOf(address(this)), IOTC.NotEnoughOutputToken());

        _changeState(OTCConstants.STATE_CANCELED);

        IERC20(INPUT_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(OUTPUT_TOKEN).safeTransfer(ADMIN_ADDRESS, outputAmount);

        emit BuybackExecuted(amount, outputAmount);
    }

    /**
     * @notice Admin executes buyback with ETH
     */
    function buybackWithEth() external payable override onlyAdmin nonReentrant {
        require(INPUT_TOKEN == address(0), IOTC.InputTokenIsToken());
        require(
            currentState == OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER
                || currentState == OTCConstants.STATE_CLIENT_REJECTED || currentState == OTCConstants.STATE_CANCELED,
            IOTC.InvalidState(currentState, OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER)
        );
        require(
            block.timestamp > proposedTime + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD, IOTC.ProposeLockActive()
        );

        uint256 amount = msg.value;
        uint256 outputAmount = (amount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        require(outputAmount <= IERC20(OUTPUT_TOKEN).balanceOf(address(this)), IOTC.NotEnoughOutputToken());

        _changeState(OTCConstants.STATE_CANCELED);

        IERC20(OUTPUT_TOKEN).safeTransfer(ADMIN_ADDRESS, outputAmount);

        emit BuybackExecuted(amount, outputAmount);
    }

    // Internal functions
    /**
     * @notice Check if minimum input amount is reached and transition to supply in progress state
     * @param currentBalance Current input token balance
     */
    function _checkAndTransitionInputState(uint256 currentBalance) internal {
        if (currentBalance >= MIN_INPUT_AMOUNT) {
            _changeState(OTCConstants.STATE_SUPPLY_IN_PROGRESS);
            supplyLockEndTime = uint64(block.timestamp) + OTCConstants.SUPPLY_LOCK_PERIOD;
            emit InputChecked(currentBalance);
        }
    }

    function _changeState(uint8 newState) internal {
        uint8 oldState = currentState;
        currentState = newState;
        emit StateChanged(oldState, newState);
    }
}

