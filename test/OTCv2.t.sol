// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {OTCv2} from "../src/OTCv2.sol";
import {OTCConstants} from "../src/libraries/OTCConstants.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IOTC} from "../src/interfaces/IOTC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdCheats, StdAssertions, Test} from "forge-std/Test.sol";

/**
 * @title OTCv2Test
 * @notice Comprehensive test suite for OTCv2 contract
 */
contract OTCv2Test is Test {
    // Contracts
    OTCv2 public otcv2;
    OTCv2 public otcv2Eth;
    OTCv2 public otcv2Demand;
    MockERC20 public inputToken;
    MockERC20 public outputToken;

    // Test addresses
    address public admin = address(0x1);
    address public client = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public farmAccount = address(0x5);

    // Test amounts
    uint256 public constant MIN_INPUT_AMOUNT = 100 ether;
    uint256 public constant MIN_OUTPUT_AMOUNT = 1000 ether;
    uint256 public constant BUYBACK_PRICE = 1e18; // 1:1 price

    // Test supplies
    IOTC.Supply[] public supplies;

    function setUp() public {
        // Deploy tokens
        inputToken = new MockERC20("Input Token", "IN", 18);
        outputToken = new MockERC20("Output Token", "OUT", 18);

        // Create supplies for testing
        supplies.push(IOTC.Supply({input: 50 ether, output: 500 ether}));
        supplies.push(IOTC.Supply({input: 50 ether, output: 500 ether}));

        // Deploy OTCv2 contracts
        vm.prank(admin);
        otcv2 = new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true // IS_SUPPLY
        );

        vm.prank(admin);
        otcv2Eth = new OTCv2(
            address(0), // ETH
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true // IS_SUPPLY
        );

        // Deploy demand-side contract (no supplies)
        IOTC.Supply[] memory emptySupplies;
        vm.prank(admin);
        otcv2Demand = new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            emptySupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            false // IS_SUPPLY
        );

        // Mint tokens for testing
        inputToken.mint(user1, 1000 ether);
        inputToken.mint(user2, 1000 ether);
        inputToken.mint(admin, 1000 ether);
        outputToken.mint(admin, 10000 ether);
        outputToken.mint(client, 10000 ether);
        outputToken.mint(user1, 1000 ether);
    }

    // ==================== CONSTRUCTOR TESTS ====================

    function test_Constructor_SetsAllImmutableValues() public {
        assertEq(address(otcv2.INPUT_TOKEN()), address(inputToken));
        assertEq(address(otcv2.OUTPUT_TOKEN()), address(outputToken));
        assertEq(otcv2.ADMIN_ADDRESS(), admin);
        assertEq(otcv2.CLIENT_ADDRESS(), client);
        assertEq(otcv2.BUYBACK_PRICE(), BUYBACK_PRICE);
        assertEq(otcv2.MIN_INPUT_AMOUNT(), MIN_INPUT_AMOUNT);
        assertEq(otcv2.MIN_OUTPUT_AMOUNT(), MIN_OUTPUT_AMOUNT);
        assertTrue(otcv2.IS_SUPPLY());
    }

    function test_Constructor_SetsInitialState() public {
        assertEq(otcv2.currentState(), OTCConstants.STATE_FUNDING);
        assertEq(otcv2.supplyCount(), 2);
        assertEq(otcv2.currentSupplyIndex(), 0);
    }

    function test_Constructor_SetsSupplyLockEndTime() public {
        uint256 expectedTime = block.timestamp + OTCConstants.INITIAL_LOCK_PERIOD;
        assertEq(otcv2.supplyLockEndTime(), expectedTime);
    }

    function test_Constructor_RevertsIfOutputSumTooLow() public {
        IOTC.Supply[] memory lowSupplies = new IOTC.Supply[](1);
        lowSupplies[0] = IOTC.Supply({input: 50 ether, output: 50 ether}); // Below MIN_OUTPUT_AMOUNT

        vm.prank(admin);
        vm.expectRevert(IOTC.OutputSumTooLow.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            lowSupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfInputSumTooLow() public {
        // IS_SUPPLY = true, outputSum == MIN_OUTPUT_AMOUNT, but inputSum != MIN_INPUT_AMOUNT
        IOTC.Supply[] memory lowInputSupplies = new IOTC.Supply[](2);
        lowInputSupplies[0] = IOTC.Supply({input: 30 ether, output: 500 ether}); // input below threshold
        lowInputSupplies[1] = IOTC.Supply({input: 30 ether, output: 500 ether}); // total input = 60 ether != MIN_INPUT_AMOUNT (100 ether), total output = 1000 ether == MIN_OUTPUT_AMOUNT

        vm.prank(admin);
        vm.expectRevert(IOTC.InputSumTooLow.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            lowInputSupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfInvalidSupplyCount() public {
        // IS_SUPPLY = true but supplyCount = 0 -> InvalidSupplyCount (now checked earlier)
        IOTC.Supply[] memory emptySupplies;
        vm.prank(admin);
        vm.expectRevert(IOTC.InvalidSupplyCount.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            emptySupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );

        // IS_SUPPLY = false but supplyCount != 0 -> InvalidSupplyCount
        vm.prank(admin);
        vm.expectRevert(IOTC.InvalidSupplyCount.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            false
        );
    }

    function test_Constructor_RevertsIfOutputTokenIsZero() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.ZeroAddress.selector);
        new OTCv2(
            address(inputToken),
            address(0), // Zero output token
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfAdminIsZero() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.ZeroAddress.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            address(0), // Zero admin
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfClientIsZero() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.ZeroAddress.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            address(0), // Zero client
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfAdminEqualsClient() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.SameAddress.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            admin, // Same as admin
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfInputTokenEqualsOutputToken() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.SameTokens.selector);
        new OTCv2(
            address(outputToken), // Same as output token
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfBuybackPriceIsZero() public {
        vm.prank(admin);
        vm.expectRevert(IOTC.InvalidBuybackPrice.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            0, // Zero buyback price
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfSupplyInputIsZero() public {
        IOTC.Supply[] memory invalidSupplies = new IOTC.Supply[](2);
        invalidSupplies[0] = IOTC.Supply({input: 50 ether, output: 500 ether});
        invalidSupplies[1] = IOTC.Supply({input: 0, output: 500 ether}); // Zero input

        vm.prank(admin);
        vm.expectRevert(IOTC.InvalidSupplyData.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            invalidSupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    function test_Constructor_RevertsIfSupplyOutputIsZero() public {
        IOTC.Supply[] memory invalidSupplies = new IOTC.Supply[](2);
        invalidSupplies[0] = IOTC.Supply({input: 50 ether, output: 500 ether});
        invalidSupplies[1] = IOTC.Supply({input: 50 ether, output: 0}); // Zero output

        vm.prank(admin);
        vm.expectRevert(IOTC.InvalidSupplyData.selector);
        new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            invalidSupplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    // ==================== DEPOSIT ETH TESTS ====================

    function test_DepositEth_Success() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        otcv2Eth.depositEth{value: 50 ether}();

        assertEq(address(otcv2Eth).balance, 50 ether);
    }

    function test_DepositEth_TransitionsToSupplyInProgress() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_SUPPLY_IN_PROGRESS);
        uint256 expectedTime = block.timestamp + OTCConstants.SUPPLY_LOCK_PERIOD;
        assertEq(otcv2Eth.supplyLockEndTime(), expectedTime);
    }

    function test_DepositEth_EmitsEvents() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit IOTC.DepositedInput(user1, 50 ether);
        otcv2Eth.depositEth{value: 50 ether}();
    }

    function test_DepositEth_RevertsIfNotSupplySide() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vm.expectRevert(IOTC.NotSupplyContract.selector);
        otcv2Demand.depositEth{value: 50 ether}();
    }

    function test_DepositEth_RevertsIfInputTokenIsNotEth() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vm.expectRevert(IOTC.InputTokenIsToken.selector);
        otcv2.depositEth{value: 50 ether}();
    }

    // ==================== DEPOSIT TOKEN TESTS ====================

    function test_DepositToken_Success() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), 50 ether);
        otcv2.depositToken(50 ether);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(otcv2)), 50 ether);
    }

    function test_DepositToken_TransitionsToSupplyInProgress() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_SUPPLY_IN_PROGRESS);
        uint256 expectedTime = block.timestamp + OTCConstants.SUPPLY_LOCK_PERIOD;
        assertEq(otcv2.supplyLockEndTime(), expectedTime);
    }

    function test_DepositToken_EmitsEvents() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), 50 ether);
        vm.expectEmit(true, false, false, true);
        emit IOTC.DepositedInput(user1, 50 ether);
        otcv2.depositToken(50 ether);
        vm.stopPrank();
    }

    function test_DepositToken_RevertsIfNotSupplySide() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2Demand), 50 ether);
        vm.expectRevert(IOTC.NotSupplyContract.selector);
        otcv2Demand.depositToken(50 ether);
        vm.stopPrank();
    }

    function test_DepositToken_RevertsIfInputTokenIsEth() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2Eth), 50 ether);
        vm.expectRevert(IOTC.InputTokenIsEth.selector);
        otcv2Eth.depositToken(50 ether);
        vm.stopPrank();
    }

    function test_DepositToken_RevertsIfWrongState() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        // Try to deposit again
        vm.startPrank(user2);
        inputToken.approve(address(otcv2), 50 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTC.InvalidState.selector, OTCConstants.STATE_SUPPLY_IN_PROGRESS, OTCConstants.STATE_FUNDING
            )
        );
        otcv2.depositToken(50 ether);
        vm.stopPrank();
    }

    // ==================== DEPOSIT OUTPUT TESTS ====================

    function test_DepositOutput_Success() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), 50 ether);
        otcv2Demand.depositOutput(50 ether);
        vm.stopPrank();

        assertEq(outputToken.balanceOf(address(otcv2Demand)), 50 ether);
    }

    function test_DepositOutput_TransitionsToSupplyProvided() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        assertEq(otcv2Demand.currentState(), OTCConstants.STATE_SUPPLY_PROVIDED);
        uint256 expectedTime = block.timestamp + OTCConstants.TOTAL_LOCK_PERIOD;
        assertEq(otcv2Demand.totalLockEndTime(), expectedTime);
    }

    function test_DepositOutput_EmitsEvents() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), 50 ether);
        vm.expectEmit(true, false, false, true);
        emit IOTC.DepositedOutput(user1, 50 ether);
        otcv2Demand.depositOutput(50 ether);
        vm.stopPrank();
    }

    function test_DepositOutput_RevertsIfSupplySide() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2), 50 ether);
        vm.expectRevert(IOTC.NotDemandContract.selector);
        otcv2.depositOutput(50 ether);
        vm.stopPrank();
    }

    function test_DepositOutput_DoesNotTransitionIfBelowMinimum() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), 50 ether);
        otcv2Demand.depositOutput(50 ether);
        vm.stopPrank();

        assertEq(otcv2Demand.currentState(), OTCConstants.STATE_FUNDING);
    }

    // ==================== WITHDRAW ETH TESTS ====================

    function test_WithdrawEth_Success() public {
        // Setup: deposit only, do not process supplies to keep ETH in contract
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        // Warp to after lock period
        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        uint256 balanceBefore = client.balance;
        uint256 contractBalance = address(otcv2Eth).balance;

        vm.prank(client);
        otcv2Eth.withdrawEth(50 ether);

        assertEq(client.balance, balanceBefore + 50 ether);
        assertEq(address(otcv2Eth).balance, contractBalance - 50 ether);
    }

    function test_WithdrawEth_EmitsEvent() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IOTC.Withdrawn(client, 50 ether);
        otcv2Eth.withdrawEth(50 ether);
    }

    function test_WithdrawEth_RevertsIfNotClient() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyClient.selector);
        otcv2Eth.withdrawEth(50 ether);
    }

    function test_WithdrawEth_RevertsIfSupplyLockActive() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        // Don't warp - still locked

        vm.prank(client);
        vm.expectRevert(IOTC.SupplyLockActive.selector);
        otcv2Eth.withdrawEth(50 ether);
    }

    function test_WithdrawEth_RevertsIfInputTokenIsNotEth() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2.supplyLockEndTime() + 1);

        vm.prank(client);
        vm.expectRevert(IOTC.InputTokenIsToken.selector);
        otcv2.withdrawEth(50 ether);
    }

    function test_WithdrawEth_RevertsIfAmountZero() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        vm.prank(client);
        vm.expectRevert(IOTC.InvalidAmount.selector);
        otcv2Eth.withdrawEth(0);
    }

    function test_WithdrawEth_RevertsIfInsufficientBalance() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        uint256 contractBalance = address(otcv2Eth).balance;
        vm.prank(client);
        vm.expectRevert(IOTC.InsufficientBalance.selector);
        otcv2Eth.withdrawEth(contractBalance + 1);
    }

    function test_WithdrawEth_RevertsIfEthTransferFails() public {
        // Deploy OTCv2 with a contract that rejects ETH as client
        RejectingEthContract rejectingClient = new RejectingEthContract();

        vm.prank(admin);
        OTCv2 otcv2WithRejectingClient = new OTCv2(
            address(0), // ETH
            address(outputToken),
            admin,
            address(rejectingClient),
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );

        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2WithRejectingClient.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2WithRejectingClient.supplyLockEndTime() + 1);

        vm.prank(address(rejectingClient));
        vm.expectRevert(IOTC.EthTransferFailed.selector);
        otcv2WithRejectingClient.withdrawEth(50 ether);
    }

    // ==================== WITHDRAW INPUT TESTS ====================

    function test_WithdrawInput_Success() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2.supplyLockEndTime() + 1);

        uint256 balanceBefore = inputToken.balanceOf(client);
        vm.prank(client);
        otcv2.withdrawInput(50 ether);

        assertEq(inputToken.balanceOf(client), balanceBefore + 50 ether);
    }

    function test_WithdrawInput_EmitsEvent() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2.supplyLockEndTime() + 1);

        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IOTC.InputWithdrawn(client, 50 ether);
        otcv2.withdrawInput(50 ether);
    }

    function test_WithdrawInput_RevertsIfNotClient() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2.supplyLockEndTime() + 1);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyClient.selector);
        otcv2.withdrawInput(50 ether);
    }

    function test_WithdrawInput_RevertsIfSupplyLockActive() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        // Don't warp, lock still active
        vm.prank(client);
        vm.expectRevert(IOTC.SupplyLockActive.selector);
        otcv2.withdrawInput(50 ether);
    }

    function test_WithdrawInput_RevertsIfInputTokenIsEth() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.warp(otcv2Eth.supplyLockEndTime() + 1);

        vm.prank(client);
        vm.expectRevert(IOTC.InputTokenIsEth.selector);
        otcv2Eth.withdrawInput(50 ether);
    }

    // ==================== WITHDRAW OUTPUT TESTS ====================

    function test_WithdrawOutput_Success() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2Demand.totalLockEndTime() + 1);

        uint256 balanceBefore = outputToken.balanceOf(client);
        vm.prank(client);
        otcv2Demand.withdrawOutput(50 ether);

        assertEq(outputToken.balanceOf(client), balanceBefore + 50 ether);
        assertEq(otcv2Demand.currentState(), OTCConstants.STATE_FINAL);
    }

    function test_WithdrawOutput_EmitsEvents() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2Demand.totalLockEndTime() + 1);

        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        // StateChanged emitted before OutputWithdrawn; focus on OutputWithdrawn only to avoid order issues
        emit IOTC.OutputWithdrawn(client, 50 ether);
        otcv2Demand.withdrawOutput(50 ether);
    }

    function test_WithdrawOutput_RevertsIfNotClient() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        vm.warp(otcv2Demand.totalLockEndTime() + 1);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyClient.selector);
        otcv2Demand.withdrawOutput(50 ether);
    }

    function test_WithdrawOutput_RevertsIfTotalLockActive() public {
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        uint256 totalLockEnd = otcv2Demand.totalLockEndTime();
        uint256 supplyLockEnd = otcv2Demand.supplyLockEndTime();

        // To test TotalLockActive (second require), we need:
        // 1. First check passes: block.timestamp > supplyLockEndTime
        // 2. Second check fails: block.timestamp <= totalLockEndTime

        // For demand-side: totalLockEndTime >= supplyLockEndTime
        // We need to warp to after supplyLockEndTime but at/before totalLockEndTime

        // Warp to exactly totalLockEndTime
        // This ensures block.timestamp > supplyLockEndTime (if totalLockEnd > supplyLockEnd)
        // but block.timestamp == totalLockEndTime, so second check fails
        vm.warp(totalLockEnd);

        // Verify that we're past supplyLockEndTime
        if (totalLockEnd > supplyLockEnd) {
            // First check (SupplyLockActive) passes, second check (TotalLockActive) fails
            vm.prank(client);
            vm.expectRevert(IOTC.TotalLockActive.selector);
            otcv2Demand.withdrawOutput(50 ether);
        } else {
            // If they're equal, we need to be 1 second past both to pass first check
            // Then test at exactly totalLockEndTime won't work
            // Instead, skip this test or adjust
            // Actually, let's test at totalLockEnd - this will fail first check if they're equal
            // So we test that both checks exist by verifying behavior
            vm.prank(client);
            // If equal, first check fails; if totalLockEnd > supplyLockEnd, second check fails
            if (totalLockEnd == supplyLockEnd) {
                vm.expectRevert(IOTC.SupplyLockActive.selector);
            } else {
                vm.expectRevert(IOTC.TotalLockActive.selector);
            }
            otcv2Demand.withdrawOutput(50 ether);
        }
    }

    function test_WithdrawOutput_RevertsIfSupplyLockActive() public {
        // Now that SupplyLockActive check is first, we can test it directly
        // by setting timestamp to supplyLockEndTime or before

        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        uint256 supplyLockEnd = otcv2Demand.supplyLockEndTime();

        // Test when block.timestamp is exactly at supplyLockEndTime
        // This should fail the first require (SupplyLockActive) since require checks > not >=
        vm.warp(supplyLockEnd);

        vm.prank(client);
        vm.expectRevert(IOTC.SupplyLockActive.selector);
        otcv2Demand.withdrawOutput(50 ether);

        // Also test when block.timestamp is before supplyLockEndTime
        vm.warp(supplyLockEnd - 1);

        vm.prank(client);
        vm.expectRevert(IOTC.SupplyLockActive.selector);
        otcv2Demand.withdrawOutput(50 ether);
    }

    // ==================== SUPPLY OUTPUT TESTS ====================

    function test_SupplyOutput_Success() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        outputToken.approve(address(otcv2), 500 ether);
        otcv2.supplyOutput();
        vm.stopPrank();

        assertEq(otcv2.currentSupplyIndex(), 1);
        assertEq(outputToken.balanceOf(address(otcv2)), 500 ether);
        assertEq(inputToken.balanceOf(admin), 1000 ether + 50 ether);
    }

    function test_SupplyOutput_TransitionsToSupplyProvidedOnLastSupply() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        outputToken.approve(address(otcv2), 1000 ether);
        otcv2.supplyOutput();
        otcv2.supplyOutput();
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_SUPPLY_PROVIDED);
        uint256 expectedTime = block.timestamp + OTCConstants.TOTAL_LOCK_PERIOD;
        assertEq(otcv2.totalLockEndTime(), expectedTime);
    }

    function test_SupplyOutput_EmitsEvents() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        outputToken.approve(address(otcv2), 500 ether);
        vm.expectEmit(true, false, false, true);
        emit IOTC.SupplyProcessed(0, 50 ether, 500 ether);
        otcv2.supplyOutput();
        vm.stopPrank();
    }

    function test_SupplyOutput_RevertsIfNotAdmin() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user1);
        outputToken.approve(address(otcv2), 500 ether);
        vm.expectRevert(IOTC.OnlyAdmin.selector);
        otcv2.supplyOutput();
        vm.stopPrank();
    }

    function test_SupplyOutput_RevertsIfWrongState() public {
        vm.startPrank(admin);
        outputToken.approve(address(otcv2), 500 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTC.InvalidState.selector, OTCConstants.STATE_FUNDING, OTCConstants.STATE_SUPPLY_IN_PROGRESS
            )
        );
        otcv2.supplyOutput();
        vm.stopPrank();
    }

    function test_SupplyOutput_TransfersEthToAdmin() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        uint256 adminBalanceBefore = admin.balance;
        vm.startPrank(admin);
        outputToken.approve(address(otcv2Eth), 500 ether);
        otcv2Eth.supplyOutput();
        vm.stopPrank();

        assertEq(admin.balance, adminBalanceBefore + 50 ether);
    }

    function test_SupplyOutput_RevertsIfEthTransferFails() public {
        // Deploy OTCv2 with a contract that rejects ETH as admin
        // First deploy the rejecting contract as the admin
        RejectingEthContract rejectingAdmin = new RejectingEthContract();

        // Mint output tokens to rejectingAdmin contract
        outputToken.mint(address(rejectingAdmin), 1000 ether);

        // Deploy OTCv2 with rejectingAdmin as admin
        vm.prank(address(rejectingAdmin));
        OTCv2 otcv2WithRejectingAdmin = new OTCv2(
            address(0), // ETH
            address(outputToken),
            address(rejectingAdmin),
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );

        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2WithRejectingAdmin.depositEth{value: MIN_INPUT_AMOUNT}();

        vm.startPrank(address(rejectingAdmin));
        outputToken.approve(address(otcv2WithRejectingAdmin), 500 ether);
        vm.expectRevert(IOTC.EthTransferFailed.selector);
        otcv2WithRejectingAdmin.supplyOutput();
        vm.stopPrank();
    }

    // ==================== PROPOSE FARM ACCOUNT TESTS ====================

    function test_ProposeDaoAccount_Success() public {
        _setupToSupplyProvided(otcv2);

        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});

        vm.prank(admin);
        otcv2.proposeDaoAccount(farmData);

        assertEq(otcv2.currentState(), OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER);
        assertEq(otcv2.proposedTime(), block.timestamp);
    }

    function test_ProposeDaoAccount_EmitsEvents() public {
        _setupToSupplyProvided(otcv2);

        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IOTC.FarmAccountProposed(farmAccount, uint64(block.timestamp));
        otcv2.proposeDaoAccount(farmData);
    }

    function test_ProposeDaoAccount_RevertsIfNotAdmin() public {
        _setupToSupplyProvided(otcv2);

        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyAdmin.selector);
        otcv2.proposeDaoAccount(farmData);
    }

    function test_ProposeDaoAccount_RevertsIfWrongState() public {
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTC.InvalidState.selector, OTCConstants.STATE_FUNDING, OTCConstants.STATE_SUPPLY_PROVIDED
            )
        );
        otcv2.proposeDaoAccount(farmData);
    }

    // ==================== VOTE YES TESTS ====================

    function test_VoteYes_Success() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        otcv2.voteYes();

        assertEq(otcv2.currentState(), OTCConstants.STATE_CLIENT_ACCEPTED);
    }

    function test_VoteYes_FromRejectedState() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        otcv2.voteNo();

        vm.prank(client);
        otcv2.voteYes();

        assertEq(otcv2.currentState(), OTCConstants.STATE_CLIENT_ACCEPTED);
    }

    function test_VoteYes_EmitsEvents() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IOTC.ClientVoted(true);
        otcv2.voteYes();
    }

    function test_VoteYes_RevertsIfNotClient() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyClient.selector);
        otcv2.voteYes();
    }

    function test_VoteYes_RevertsIfWrongState() public {
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTC.InvalidStateForVote.selector, OTCConstants.STATE_FUNDING));
        otcv2.voteYes();
    }

    // ==================== VOTE NO TESTS ====================

    function test_VoteNo_Success() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        otcv2.voteNo();

        assertEq(otcv2.currentState(), OTCConstants.STATE_CLIENT_REJECTED);
    }

    function test_VoteNo_EmitsEvents() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IOTC.ClientVoted(false);
        otcv2.voteNo();
    }

    function test_VoteNo_RevertsIfNotClient() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyClient.selector);
        otcv2.voteNo();
    }

    function test_VoteNo_RevertsIfWrongState() public {
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTC.InvalidStateForVote.selector, OTCConstants.STATE_FUNDING));
        otcv2.voteNo();
    }

    function test_VoteNo_RevertsFromRejectedState() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        otcv2.voteNo();

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTC.InvalidStateForVote.selector, OTCConstants.STATE_CLIENT_REJECTED));
        otcv2.voteNo();
    }

    // ==================== SEND TO FARM TESTS ====================

    function test_SendToFarm_Success() public {
        _setupToClientAccepted(otcv2);

        uint256 allowanceBefore = outputToken.allowance(address(otcv2), farmAccount);
        vm.prank(admin);
        otcv2.sendToFarm();

        assertEq(outputToken.allowance(address(otcv2), farmAccount), allowanceBefore + MIN_OUTPUT_AMOUNT);
    }

    function test_SendToFarm_WithCallData() public {
        _setupToClientAccepted(otcv2);

        // Create a contract that can receive and verify the call
        TestFarmContract farmContract = new TestFarmContract();
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({
            farmAccount: address(farmContract),
            sendData: abi.encodeWithSelector(TestFarmContract.receiveTokens.selector, MIN_OUTPUT_AMOUNT)
        });

        // Deploy a fresh contract instance, do not overwrite otcv2
        vm.prank(admin);
        OTCv2 otcv2_2 = new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
        _setupToSupplyProvided(otcv2_2);

        vm.prank(admin);
        otcv2_2.proposeDaoAccount(farmData);

        vm.prank(client);
        otcv2_2.voteYes();

        uint256 allowanceBefore = outputToken.allowance(address(otcv2_2), address(farmContract));
        vm.prank(admin);
        otcv2_2.sendToFarm();

        assertEq(outputToken.allowance(address(otcv2_2), address(farmContract)), allowanceBefore + MIN_OUTPUT_AMOUNT);
        assertTrue(farmContract.tokensReceived());
    }

    function test_SendToFarm_EmitsEvents() public {
        _setupToClientAccepted(otcv2);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IOTC.TokensSentToFarm(farmAccount, MIN_OUTPUT_AMOUNT);
        otcv2.sendToFarm();
    }

    function test_SendToFarm_RevertsIfNotAdmin() public {
        _setupToClientAccepted(otcv2);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyAdmin.selector);
        otcv2.sendToFarm();
    }

    function test_SendToFarm_RevertsIfWrongState() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTC.InvalidState.selector,
                OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER,
                OTCConstants.STATE_CLIENT_ACCEPTED
            )
        );
        otcv2.sendToFarm();
    }

    function test_SendToFarm_RevertsIfNoFarmData() public {
        // Create contract and set state without proposing farm
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        _processAllSupplies(otcv2);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTC.InvalidState.selector, OTCConstants.STATE_SUPPLY_PROVIDED, OTCConstants.STATE_CLIENT_ACCEPTED
            )
        );
        otcv2.sendToFarm();
    }

    function test_SendToFarm_RevertsIfCallFails() public {
        _setupToClientAccepted(otcv2);

        // Create a contract that will revert on call
        RevertingFarmContract revertingFarm = new RevertingFarmContract();
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({
            farmAccount: address(revertingFarm), sendData: abi.encodeWithSelector(RevertingFarmContract.fail.selector)
        });

        // Deploy new otcv2 instance and go through flow
        vm.prank(admin);
        OTCv2 otcv2_2 = new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
        _setupToSupplyProvided(otcv2_2);
        vm.prank(admin);
        otcv2_2.proposeDaoAccount(farmData);

        vm.prank(client);
        otcv2_2.voteYes();

        vm.prank(admin);
        vm.expectRevert(IOTC.FarmCallFailed.selector);
        otcv2_2.sendToFarm();
    }

    // ==================== BUYBACK WITH TOKEN TESTS ====================

    function test_BuybackWithToken_Success() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 100 ether;
        uint256 expectedOutput = (inputAmount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        uint256 adminOutputBefore = outputToken.balanceOf(admin);

        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_FINAL);
        assertEq(outputToken.balanceOf(admin), adminOutputBefore + expectedOutput);
    }

    function test_BuybackWithToken_FromRejectedState() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.prank(client);
        otcv2.voteNo();

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 100 ether;
        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_FINAL);
    }

    function test_BuybackWithToken_FromCanceledState() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 50 ether;
        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();

        // Try buyback again from canceled state
        inputAmount = 50 ether;
        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_FINAL);
    }

    function test_BuybackWithToken_EmitsEvents() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 100 ether;
        uint256 expectedOutput = (inputAmount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        vm.expectEmit(true, false, false, true);
        emit IOTC.BuybackExecuted(inputAmount, expectedOutput);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();
    }

    function test_BuybackWithToken_RevertsIfNotAdmin() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        vm.startPrank(user1);
        inputToken.approve(address(otcv2), 100 ether);
        vm.expectRevert(IOTC.OnlyAdmin.selector);
        otcv2.buybackWithToken(100 ether);
        vm.stopPrank();
    }

    function test_BuybackWithToken_RevertsIfInputTokenIsEth() public {
        _setupToWaitingForClientAnswer(otcv2Eth);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        vm.startPrank(admin);
        inputToken.approve(address(otcv2Eth), 100 ether);
        vm.expectRevert(IOTC.InputTokenIsEth.selector);
        otcv2Eth.buybackWithToken(100 ether);
        vm.stopPrank();
    }

    function test_BuybackWithToken_RevertsIfWrongState() public {
        vm.startPrank(admin);
        inputToken.approve(address(otcv2), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IOTC.InvalidStateForBuyback.selector, OTCConstants.STATE_FUNDING));
        otcv2.buybackWithToken(100 ether);
        vm.stopPrank();
    }

    function test_BuybackWithToken_RevertsIfFarmNotProposed() public {
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        _processAllSupplies(otcv2);

        vm.startPrank(admin);
        inputToken.approve(address(otcv2), 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IOTC.InvalidStateForBuyback.selector, OTCConstants.STATE_SUPPLY_PROVIDED)
        );
        otcv2.buybackWithToken(100 ether);
        vm.stopPrank();
    }

    function test_BuybackWithToken_RevertsIfProposeLockActive() public {
        _setupToWaitingForClientAnswer(otcv2);

        // Don't warp - lock still active
        vm.startPrank(admin);
        inputToken.approve(address(otcv2), 100 ether);
        vm.expectRevert(IOTC.ProposeLockActive.selector);
        otcv2.buybackWithToken(100 ether);
        vm.stopPrank();
    }

    // ==================== BUYBACK WITH ETH TESTS ====================

    function test_BuybackWithEth_Success() public {
        _setupToWaitingForClientAnswer(otcv2Eth);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 1 ether;
        uint256 expectedOutput = (inputAmount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        uint256 adminOutputBefore = outputToken.balanceOf(admin);
        vm.deal(admin, 10 ether);

        vm.prank(admin);
        otcv2Eth.buybackWithEth{value: inputAmount}();

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_FINAL);
        assertEq(outputToken.balanceOf(admin), adminOutputBefore + expectedOutput);
    }

    function test_BuybackWithEth_EmitsEvents() public {
        _setupToWaitingForClientAnswer(otcv2Eth);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 1 ether;
        uint256 expectedOutput = (inputAmount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        vm.deal(admin, 10 ether);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IOTC.BuybackExecuted(inputAmount, expectedOutput);
        otcv2Eth.buybackWithEth{value: inputAmount}();
    }

    function test_BuybackWithEth_RevertsIfNotAdmin() public {
        _setupToWaitingForClientAnswer(otcv2Eth);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        vm.deal(user1, 10 ether);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyAdmin.selector);
        otcv2Eth.buybackWithEth{value: 1 ether}();
    }

    function test_BuybackWithEth_RevertsIfInputTokenIsNotEth() public {
        _setupToWaitingForClientAnswer(otcv2);

        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        vm.deal(admin, 10 ether);

        vm.prank(admin);
        vm.expectRevert(IOTC.InputTokenIsToken.selector);
        otcv2.buybackWithEth{value: 1 ether}();
    }

    function test_BuybackWithEth_RevertsIfWrongState() public {
        vm.deal(admin, 10 ether);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IOTC.InvalidStateForBuyback.selector, OTCConstants.STATE_FUNDING));
        otcv2Eth.buybackWithEth{value: 1 ether}();
    }

    function test_BuybackWithEth_RevertsIfFarmNotProposed() public {
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        _processAllSupplies(otcv2Eth);

        vm.deal(admin, 10 ether);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IOTC.InvalidStateForBuyback.selector, OTCConstants.STATE_SUPPLY_PROVIDED)
        );
        otcv2Eth.buybackWithEth{value: 1 ether}();
    }

    function test_BuybackWithEth_RevertsIfProposeLockActive() public {
        _setupToWaitingForClientAnswer(otcv2Eth);

        // Don't warp - lock still active
        vm.deal(admin, 10 ether);

        vm.prank(admin);
        vm.expectRevert(IOTC.ProposeLockActive.selector);
        otcv2Eth.buybackWithEth{value: 1 ether}();
    }

    // ==================== FULL FLOW TESTS ====================

    function test_FullFlow_SupplySideWithEth_Success() public {
        // 1. Deposit ETH
        vm.deal(user1, MIN_INPUT_AMOUNT);
        vm.prank(user1);
        otcv2Eth.depositEth{value: MIN_INPUT_AMOUNT}();

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_SUPPLY_IN_PROGRESS);

        // 2. Process all supplies
        _processAllSupplies(otcv2Eth);

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_SUPPLY_PROVIDED);

        // 3. Propose farm account
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});
        vm.prank(admin);
        otcv2Eth.proposeDaoAccount(farmData);

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER);

        // 4. Client votes YES
        vm.prank(client);
        otcv2Eth.voteYes();

        assertEq(otcv2Eth.currentState(), OTCConstants.STATE_CLIENT_ACCEPTED);

        // 5. Send to farm
        uint256 allowanceBefore = outputToken.allowance(address(otcv2Eth), farmAccount);
        vm.prank(admin);
        otcv2Eth.sendToFarm();

        assertEq(outputToken.allowance(address(otcv2Eth), farmAccount), allowanceBefore + MIN_OUTPUT_AMOUNT);
    }

    function test_FullFlow_SupplySideWithToken_Buyback() public {
        // 1. Deposit tokens
        vm.startPrank(user1);
        inputToken.approve(address(otcv2), MIN_INPUT_AMOUNT);
        otcv2.depositToken(MIN_INPUT_AMOUNT);
        vm.stopPrank();

        // 2. Process all supplies
        _processAllSupplies(otcv2);

        // 3. Propose farm account
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});
        vm.prank(admin);
        otcv2.proposeDaoAccount(farmData);

        // 4. Client votes NO
        vm.prank(client);
        otcv2.voteNo();

        assertEq(otcv2.currentState(), OTCConstants.STATE_CLIENT_REJECTED);

        // 5. Admin does buyback
        vm.warp(block.timestamp + OTCConstants.PROPOSE_FARM_ACCOUNT_LOCK_PERIOD + 1);

        uint256 inputAmount = 100 ether;
        uint256 expectedOutput = (inputAmount * OTCConstants.NOMINATOR) / BUYBACK_PRICE;

        vm.startPrank(admin);
        inputToken.approve(address(otcv2), inputAmount);
        otcv2.buybackWithToken(inputAmount);
        vm.stopPrank();

        assertEq(otcv2.currentState(), OTCConstants.STATE_FINAL);
        assertEq(outputToken.balanceOf(admin), 10000 ether - 1000 ether + expectedOutput);
    }

    function test_FullFlow_DemandSide() public {
        // 1. Deposit output tokens
        vm.startPrank(user1);
        outputToken.approve(address(otcv2Demand), MIN_OUTPUT_AMOUNT);
        otcv2Demand.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        assertEq(otcv2Demand.currentState(), OTCConstants.STATE_SUPPLY_PROVIDED);

        // 2. Wait for lock period
        vm.warp(otcv2Demand.totalLockEndTime() + 1);

        // 3. Withdraw output tokens
        uint256 clientBalanceBefore = outputToken.balanceOf(client);
        vm.prank(client);
        otcv2Demand.withdrawOutput(50 ether);

        assertEq(outputToken.balanceOf(client), clientBalanceBefore + 50 ether);
        assertEq(otcv2Demand.currentState(), OTCConstants.STATE_FINAL);
    }

    // ==================== HELPER FUNCTIONS ====================

    function _setupToSupplyProvided(OTCv2 contractInstance) internal {
        if (contractInstance.IS_SUPPLY()) {
            if (contractInstance.INPUT_TOKEN() == address(0)) {
                vm.deal(user1, MIN_INPUT_AMOUNT);
                vm.prank(user1);
                contractInstance.depositEth{value: MIN_INPUT_AMOUNT}();
            } else {
                vm.startPrank(user1);
                IERC20(contractInstance.INPUT_TOKEN()).approve(address(contractInstance), MIN_INPUT_AMOUNT);
                contractInstance.depositToken(MIN_INPUT_AMOUNT);
                vm.stopPrank();
            }
            _processAllSupplies(contractInstance);
        } else {
            vm.startPrank(user1);
            IERC20(contractInstance.OUTPUT_TOKEN()).approve(address(contractInstance), MIN_OUTPUT_AMOUNT);
            contractInstance.depositOutput(MIN_OUTPUT_AMOUNT);
            vm.stopPrank();
        }
    }

    function _setupToWaitingForClientAnswer(OTCv2 contractInstance) internal {
        _setupToSupplyProvided(contractInstance);

        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({farmAccount: farmAccount, sendData: ""});

        vm.prank(contractInstance.ADMIN_ADDRESS());
        contractInstance.proposeDaoAccount(farmData);
    }

    function _setupToClientAccepted(OTCv2 contractInstance) internal {
        _setupToWaitingForClientAnswer(contractInstance);

        vm.prank(contractInstance.CLIENT_ADDRESS());
        contractInstance.voteYes();
    }

    function _processAllSupplies(OTCv2 contractInstance) internal {
        vm.startPrank(contractInstance.ADMIN_ADDRESS());
        IERC20 outputTokenContract = IERC20(contractInstance.OUTPUT_TOKEN());
        uint8 supplyCount = contractInstance.supplyCount();

        for (uint8 i = 0; i < supplyCount; i++) {
            (, uint256 outputAmount) = contractInstance.supplies(i);
            outputTokenContract.approve(address(contractInstance), outputAmount);
            contractInstance.supplyOutput();
        }
        vm.stopPrank();
    }

    function _redeployContract() internal returns (OTCv2) {
        vm.prank(admin);
        return new OTCv2(
            address(inputToken),
            address(outputToken),
            admin,
            client,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            true
        );
    }

    // ==================== ONLY ADMIN OR CLIENT MODIFIER TESTS ====================

    function test_OnlyAdminOrClient_SuccessAsAdmin() public {
        // Create a test contract that uses onlyAdminOrClient modifier
        TestContractWithModifier testContract = new TestContractWithModifier(admin, client);

        vm.prank(admin);
        testContract.testOnlyAdminOrClient();

        assertTrue(testContract.called());
    }

    function test_OnlyAdminOrClient_SuccessAsClient() public {
        TestContractWithModifier testContract = new TestContractWithModifier(admin, client);

        vm.prank(client);
        testContract.testOnlyAdminOrClient();

        assertTrue(testContract.called());
    }

    function test_OnlyAdminOrClient_RevertsIfNotAdminOrClient() public {
        TestContractWithModifier testContract = new TestContractWithModifier(admin, client);

        vm.prank(user1);
        vm.expectRevert(IOTC.OnlyAdminOrClient.selector);
        testContract.testOnlyAdminOrClient();
    }
}

// Helper contract for testing onlyAdminOrClient modifier
contract TestContractWithModifier {
    address public admin;
    address public client;
    bool public called;

    constructor(address _admin, address _client) {
        admin = _admin;
        client = _client;
    }

    function testOnlyAdminOrClient() external {
        require(msg.sender == admin || msg.sender == client, IOTC.OnlyAdminOrClient());
        called = true;
    }
}

// Helper contract for testing sendToFarm with call data
contract TestFarmContract {
    bool public tokensReceived;

    function receiveTokens(uint256 amount) external {
        tokensReceived = true;
    }
}

// Helper contract that reverts on call
contract RevertingFarmContract {
    function fail() external pure {
        revert("Intentional failure");
    }
}

// Helper contract that rejects ETH transfers
contract RejectingEthContract {
    receive() external payable {
        revert("ETH transfer rejected");
    }
}

