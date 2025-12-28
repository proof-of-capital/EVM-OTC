// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {OTCv2} from "../src/OTCv2.sol";
import {OTCConstants} from "../src/libraries/OTCConstants.sol";
import {IOTC} from "../src/interfaces/IOTC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdCheats, StdAssertions, Test} from "forge-std/Test.sol";
import {DAO} from "../lib/DAO-EVM/src/DAO.sol";
import {DataTypes} from "../lib/DAO-EVM/src/utils/DataTypes.sol";
import {Constants} from "../lib/DAO-EVM/src/utils/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title OTCv2ForkBSCTest
 * @notice Fork test on BSC for OTCv2 demand-side contract integration with DAO
 */
contract OTCv2ForkBSCTest is Test {
    // BSC RPC URL constant
    string constant BSC_RPC_URL = "https://bsc-dataseed1.binance.org";

    // BSC token addresses
    address constant BSC_USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    
    // BSC Chainlink price feed addresses
    // USDT/USD price feed on BSC
    address constant BSC_USDT_PRICE_FEED = 0xB97Ad0E74fa7d920791E90258A6E2085088b4320;

    // Contracts
    OTCv2 public otcv2;
    DAO public dao;
    MockERC20 public launchToken;

    // Test addresses
    address public admin;
    address public client;
    address public user1;

    // Test amounts from OTCv2.s.sol
    uint256 public constant BUYBACK_PRICE = 1e18;
    uint256 public constant MIN_OUTPUT_AMOUNT = 1000 * 1e18; // 1000 USDT
    uint256 public constant MIN_INPUT_AMOUNT = 0;
    bool public constant IS_SUPPLY = false; // demand-side

    // DAO parameters
    uint256 public vaultId;
    uint256 public depositAmount;

    function setUp() public {
        // Create BSC fork
        vm.createSelectFork(BSC_RPC_URL);

        // Set up test addresses
        admin = address(this);
        client = address(0x2);
        user1 = address(0x3);

        // Deploy mock launch token for DAO
        launchToken = new MockERC20("Launch Token", "LAUNCH", 18);
        launchToken.mint(admin, 1000000 * 1e18);

        // Deploy OTCv2 contract with parameters from OTCv2.s.sol
        IOTC.Supply[] memory emptySupplies = new IOTC.Supply[](0);
        
        otcv2 = new OTCv2(
            BSC_USDC,      // INPUT_TOKEN
            BSC_USDT,      // OUTPUT_TOKEN
            admin,         // ADMIN_ADDRESS
            client,        // CLIENT_ADDRESS
            emptySupplies, // Empty supplies for demand-side
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            IS_SUPPLY      // false for demand-side
        );

        // Deploy and initialize DAO contract
        _deployAndInitializeDAO();

        // Create vault in DAO
        vaultId = dao.createVault(address(0x4), address(0x5), address(0x6));
        
        // Set deposit limit for vault (admin can set limit)
        // Set a high limit to allow the deposit
        vm.prank(admin);
        dao.setVaultDepositLimit(vaultId, type(uint256).max);
        
        // Set deposit amount (MIN_OUTPUT_AMOUNT from OTCv2)
        depositAmount = MIN_OUTPUT_AMOUNT;
    }

    function _deployAndInitializeDAO() internal {
        // Deploy DAO implementation
        DAO daoImplementation = new DAO();

        // Prepare minimal constructor parameters
        DataTypes.ConstructorParams memory params = DataTypes.ConstructorParams({
            launchToken: address(launchToken),
            mainCollateral: BSC_USDT, // USDT as main collateral
            creator: admin,
            creatorProfitPercent: 4000, // 40%
            creatorInfraPercent: 1000,  // 10%
            royaltyRecipient: address(0),
            royaltyPercent: 0,
            minDeposit: 100 * 1e18, // $100 minimum
            minLaunchDeposit: 10000 * 1e18,
            sharePrice: 1000 * 1e18, // $1000 per share
            launchPrice: 0.1 * 1e18, // $0.1 per launch token
            targetAmountMainCollateral: 200000 * 1e18, // $200k target
            fundraisingDuration: 30 days,
            extensionPeriod: 14 days,
            collateralTokens: _createAddressArray(BSC_USDT), // Add USDT as collateral
            priceFeeds: _createAddressArray(BSC_USDT_PRICE_FEED), // Add USDT price feed
            routers: new address[](0),
            tokens: new address[](0),
            pocParams: _createPOCParamsArray(BSC_USDT, BSC_USDT_PRICE_FEED), // Add USDT as POC to make it sellable
            rewardTokenParams: new DataTypes.RewardTokenConstructorParams[](0),
            orderbookParams: DataTypes.OrderbookConstructorParams({
                initialPrice: 1 * 1e18, // $1
                initialVolume: 10000 * 1e18,
                priceStepPercent: 500, // 5%
                volumeStepPercent: -100, // -1%
                proportionalityCoefficient: 7500, // 0.75
                totalSupply: 1e27 // 1 billion
            }),
            primaryLPTokenType: DataTypes.LPTokenType.V2,
            v3LPPositions: new DataTypes.V3LPPositionParams[](0)
        });

        // Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(DAO.initialize.selector, params);

        // Deploy ERC1967Proxy with implementation and initialize call
        ERC1967Proxy proxy = new ERC1967Proxy(address(daoImplementation), initData);
        dao = DAO(payable(address(proxy)));
    }

    // Helper function to create address array with one element
    function _createAddressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    // Helper function to create POC params array with USDT
    // Using mock POC contract address (can be any address for testing)
    function _createPOCParamsArray(address collateralToken, address priceFeed) internal pure returns (DataTypes.POCConstructorParams[] memory) {
        DataTypes.POCConstructorParams[] memory pocParams = new DataTypes.POCConstructorParams[](1);
        // Use a mock address for POC contract (e.g., admin address or a test address)
        // The actual POC contract address doesn't matter for making collateral sellable
        pocParams[0] = DataTypes.POCConstructorParams({
            pocContract: address(0x1234567890123456789012345678901234567890), // Mock POC contract address
            collateralToken: collateralToken, // USDT
            priceFeed: priceFeed, // USDT price feed
            sharePercent: 10000 // 100% share (BASIS_POINTS = 10000)
        });
        return pocParams;
    }

    function test_MainPath_DemandSide_ThenDepositToDAO() public {
        // Get USDT token interface
        IERC20 usdt = IERC20(BSC_USDT);

        // Check initial state
        assertEq(otcv2.currentState(), OTCConstants.STATE_FUNDING);
        assertEq(otcv2.supplyCount(), 0);
        assertEq(otcv2.IS_SUPPLY(), false);

        // Get USDT from a whale on BSC for testing
        // Using a known USDT holder on BSC
        address usdtWhale = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3; // Binance hot wallet
        vm.startPrank(usdtWhale);
        uint256 whaleBalance = usdt.balanceOf(usdtWhale);
        require(whaleBalance >= MIN_OUTPUT_AMOUNT, "Insufficient USDT in whale wallet");
        
        // Transfer USDT to user1
        usdt.transfer(user1, MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        // Step 1: Deposit output tokens (USDT) to OTCv2
        vm.startPrank(user1);
        usdt.approve(address(otcv2), MIN_OUTPUT_AMOUNT);
        otcv2.depositOutput(MIN_OUTPUT_AMOUNT);
        vm.stopPrank();

        // Check state transition to SUPPLY_PROVIDED
        assertEq(otcv2.currentState(), OTCConstants.STATE_SUPPLY_PROVIDED);
        assertEq(usdt.balanceOf(address(otcv2)), MIN_OUTPUT_AMOUNT);

        // Step 2: Encode depositFundraising call
        bytes memory sendData = abi.encodeWithSelector(
            DAO.depositFundraising.selector,
            depositAmount, // amount of USDT to deposit
            vaultId         // vault ID in DAO
        );

        // Step 3: Create FarmWithdrawData with DAO as farm account
        IOTC.FarmWithdrawData memory farmData = IOTC.FarmWithdrawData({
            farmAccount: address(dao),
            sendData: sendData
        });

        // Step 4: Propose DAO account
        vm.prank(admin);
        otcv2.proposeDaoAccount(farmData);

        // Check state transition
        assertEq(otcv2.currentState(), OTCConstants.STATE_WAITING_FOR_CLIENT_ANSWER);

        // Step 5: Client votes YES
        vm.prank(client);
        otcv2.voteYes();

        // Check state transition
        assertEq(otcv2.currentState(), OTCConstants.STATE_CLIENT_ACCEPTED);

        // Step 6: Send to farm (this will execute depositFundraising)
        uint256 daoBalanceBefore = usdt.balanceOf(address(dao));
        uint256 otcv2BalanceBefore = usdt.balanceOf(address(otcv2));
        uint256 vaultDepositBefore = dao.vaultMainCollateralDeposit(vaultId);
        DataTypes.Vault memory vaultBefore = dao.vaults(vaultId);
        uint256 vaultSharesBefore = vaultBefore.shares;

        vm.prank(admin);
        otcv2.sendToFarm();

        // Verify depositFundraising was executed
        uint256 daoBalanceAfter = usdt.balanceOf(address(dao));
        uint256 otcv2BalanceAfter = usdt.balanceOf(address(otcv2));
        uint256 vaultDepositAfter = dao.vaultMainCollateralDeposit(vaultId);
        DataTypes.Vault memory vaultAfter = dao.vaults(vaultId);
        uint256 vaultSharesAfter = vaultAfter.shares;

        // Check that USDT was transferred to DAO
        assertEq(daoBalanceAfter, daoBalanceBefore + depositAmount);
        
        // Check that OTCv2 balance decreased (allowance was used)
        // Note: sendToFarm increases allowance, then DAO transfers from OTCv2
        assertLt(otcv2BalanceAfter, otcv2BalanceBefore);
        
        // Check that vault deposit increased
        assertEq(vaultDepositAfter, vaultDepositBefore + depositAmount);
        
        // Check that vault shares increased and are greater than zero
        assertGt(vaultSharesAfter, 0);
        assertGt(vaultSharesAfter, vaultSharesBefore);
    }
}

