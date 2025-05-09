// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {Test, console, stdError} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DecentralizedStablecoin dsc;
    DSCEngine engine;
    address[] tokens;
    address[] feeds;
    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");
    uint256 constant INITIAL_VALUE = 10 ether;
    uint256 constant INITIAL_ALLOWANCE = 10 ether;
    int256 private constant NEW_ETH_PRICE = 1000e8;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    uint256 maxBorrowableDSC;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, tokens, feeds) = deployer.run();
        weth = tokens[0];
        ethUsdPriceFeed = feeds[0];
        btcUsdPriceFeed = feeds[1];
        ERC20Mock(weth).mint(USER, INITIAL_VALUE);
        maxBorrowableDSC = engine.getTokenUSDValue(weth, INITIAL_VALUE) * engine.getLiquidationThreshold()
            / engine.getLiquidationPrecision();
    }
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TEST
    //////////////////////////////////////////////////////////////*/

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function test_Revert_IfTokenLengthDoesnotMatchPriceFeeds() external {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }
    /*//////////////////////////////////////////////////////////////
                               PRICE TEST
    //////////////////////////////////////////////////////////////*/

    function testGetTokenUSDValue() external view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000 = 30,000 e18
        uint256 expectedPrice = 30_000e18;
        uint256 resultantPrice = engine.getTokenUSDValue(weth, ethAmount);
        assertEq(expectedPrice, resultantPrice);
    }

    function testGetTokenAmountFromUsd() external view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assert(expectedWeth == actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                              BASIC TESTS
    //////////////////////////////////////////////////////////////*/
    function testOwnerOfDSCIsEngine() external view {
        address owner = dsc.owner();
        assertEq(address(engine), owner);
    }

    function testDSCNameAndSymbol() external view {
        string memory name = "Decentralized Stable coin";
        string memory symbol = "DSC";
        assert(keccak256(abi.encode(name)) == keccak256(abi.encode(dsc.name())));
        assert(keccak256(abi.encode(symbol)) == keccak256(abi.encode(dsc.symbol())));
    }

    /*//////////////////////////////////////////////////////////////
                           BASIC ENGINE TESTS
    //////////////////////////////////////////////////////////////*/
    function testMintEth() external view {
        assertEq(ERC20Mock(weth).balanceOf(USER), INITIAL_VALUE);
    }

    function testMintBtc() external {
        vm.prank(USER);
        address wbtc = tokens[1];
        ERC20Mock(wbtc).mint(USER, INITIAL_VALUE);
        assertEq(ERC20Mock(wbtc).balanceOf(USER), INITIAL_VALUE);
    }

    function testOnlyEngineCanCallMintDSC() external {
        bytes memory expectedError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER);
        vm.expectRevert(expectedError);
        vm.prank(USER);
        dsc.mint(USER, INITIAL_VALUE);
    }

    function testOnlyEngineCanCallBurnDSC() external {
        bytes memory expectedError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER);
        vm.expectRevert(expectedError);
        vm.prank(USER);
        dsc.burn(INITIAL_VALUE);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        engine.depositCollateral(weth, INITIAL_VALUE);
        vm.stopPrank();
        _;
    }

    function test_Revert_IfCollateralZero() external {
        uint256 amountCollateral = 0;
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        vm.prank(USER);
        engine.depositCollateral(weth, amountCollateral);
    }

    function test_Reverts_WithUnApprovedCollateral() external {
        ERC20Mock erc20Mock = new ERC20Mock();
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector);
        vm.prank(USER);
        engine.depositCollateral(address(erc20Mock), INITIAL_VALUE);
    }

    function test_Revert_IfDepositEthCollateralWithoutApproval() external {
        address spender = address(engine);
        uint256 currentAllowance = 0;
        uint256 value = INITIAL_VALUE;

        bytes memory expectedError =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, currentAllowance, value);
        vm.prank(USER);
        vm.expectRevert(expectedError);
        engine.depositCollateral(weth, INITIAL_VALUE);
    }

    function test_ApproveEngineToSpendDepositCollateral() external {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        assertEq(ERC20Mock(weth).allowance(USER, address(engine)), INITIAL_ALLOWANCE);
    }

    function testDepositEthCollateralEmitsEvent() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);

        assertEq(ERC20Mock(weth).allowance(USER, address(engine)), INITIAL_ALLOWANCE);

        vm.recordLogs();
        engine.depositCollateral(weth, INITIAL_VALUE);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 eventSig = keccak256("CollateralDeposited(address,address,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                address caller = address(uint160(uint256(logs[i].topics[1])));
                address token = address(uint160(uint256(logs[i].topics[2])));
                assertEq(caller, USER, "Caller is USER address");
                assertEq(token, weth, "Collateral is wETH");
            }
        }
    }

    function testDepositCollateralAndGetAccountInfo() external depositedCollateral {
        (uint256 dscMinted, uint256 accountCollateralUSD) = engine.getAccountInfo(USER);

        uint256 expectedCollateralUSD = engine.getTokenUSDValue(weth, INITIAL_VALUE);
        uint256 expectedCollateral = engine.getTokenAmountFromUsd(weth, accountCollateralUSD);

        assertEq(expectedCollateralUSD, accountCollateralUSD);
        assertEq(expectedCollateral, INITIAL_VALUE);
        assertEq(dscMinted, 0);
    }

    function testFetchDepositedCollateral() external depositedCollateral {
        uint256 expectedCollateral = engine.getCollateralDeposited(USER, weth);
        assertEq(expectedCollateral, INITIAL_VALUE);
    }

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    function test_Revert_WhenMintedDSCIsZero() external {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDSC(0);
    }

    function test_Revert_WhenDSCMintedWithZeroCollateral() external {
        uint256 dscMintAmount = 2 ether;

        uint256 collateralValueInUSD = engine.getTokenUSDValue(weth, 0);
        uint256 healthFactor = engine.calculateHealthFactor(dscMintAmount, collateralValueInUSD);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, USER, healthFactor));
        vm.prank(USER);
        engine.mintDSC(dscMintAmount);
    }

    function test_Revert_WhenMintedMoreThanMaxBorrowableLimit() external depositedCollateral {
        uint256 collateralValueInUSD = engine.getTokenUSDValue(weth, INITIAL_VALUE);
        uint256 healthFactor = engine.calculateHealthFactor(maxBorrowableDSC + 1, collateralValueInUSD);

        bytes memory expectedError =
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, USER, healthFactor);
        vm.expectRevert(expectedError);
        vm.prank(USER);
        engine.mintDSC(maxBorrowableDSC + 1);
    }

    function test_MintSuccessWhenBorrowedLessThanMaxLimit() external depositedCollateral {
        vm.prank(USER);
        vm.recordLogs();
        engine.mintDSC(maxBorrowableDSC - 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 dscTokenMinted,) = engine.getAccountInfo(USER);
        bytes32 signature = keccak256("DSCMinted(address,uint256)");

        assertEq(dscTokenMinted, maxBorrowableDSC - 1);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == signature) {
                console.log("Inside signature");
                address user = address(uint160(uint256(logs[i].topics[1])));
                uint256 amountMinted = uint256(bytes32(logs[i].data));
                assertEq(user, USER);
                assertEq(amountMinted, maxBorrowableDSC - 1);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSITCOLLATERAL AND MINTDSC
    //////////////////////////////////////////////////////////////*/
    function test_DepositCollateralAndMintDSC() external {
        uint256 tokenUSDValue = engine.getTokenUSDValue(weth, INITIAL_VALUE);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, maxBorrowableDSC);
        (uint256 dscMinted, uint256 accountCollateralValueUSD) = engine.getAccountInfo(USER);
        vm.stopPrank();

        assertEq(dscMinted, maxBorrowableDSC);
        assertEq(accountCollateralValueUSD, tokenUSDValue);
    }

    /*//////////////////////////////////////////////////////////////
                           REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function test_Revert_IfCollateralForRedemptionIsZero() external {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function test_Revert_IfUnapprovedCollateralUsedForRedemption() external {
        ERC20Mock mock = new ERC20Mock();
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector);
        engine.redeemCollateral(address(mock), INITIAL_VALUE);
    }

    function test_Revert_RedeemCollateralWithZeroDSCMinted() external depositedCollateral {
        vm.prank(USER);
        engine.redeemCollateral(weth, INITIAL_VALUE);
        uint256 remainingCollateral = engine.getCollateralDeposited(USER, weth);
        assertEq(remainingCollateral, 0);
    }

    function test_RedeemCollateralWithDepsoitCollateralAndMintDSC() external {
        //Collateral Deposited = 2 * INITIAL_VALUE;
        uint256 dscToMint = 5 ether;
        uint256 collateralToRedeem = 5 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, INITIAL_VALUE); //weth Minted -> 2 * INITIAL_VALUE
        ERC20Mock(weth).approve(address(engine), 2 * INITIAL_ALLOWANCE);
        uint256 collateralBeforeDeposit = ERC20Mock(weth).balanceOf(USER);
        engine.depositCollateral(weth, INITIAL_VALUE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, dscToMint);
        engine.redeemCollateral(weth, collateralToRedeem);
        vm.stopPrank();

        uint256 collateralLocked = engine.getCollateralDeposited(USER, weth);
        uint256 collateralAfterDeposit = ERC20Mock(weth).balanceOf(USER);

        assertEq(collateralBeforeDeposit - collateralAfterDeposit, collateralLocked);
    }
    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/

    function test_Revert_WithBurnZeroDSC() external {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.burnDSC(0);
    }

    function testCannotBurnWithoutMintingDSC() external {
        uint256 amountToBurn = 1 ether;
        vm.prank(USER);
        vm.expectRevert(stdError.arithmeticError);
        engine.burnDSC(amountToBurn);
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, maxBorrowableDSC);
        vm.stopPrank();
        _;
    }

    function test_Revert_BurnDSCWhenEngineNotApproved() external depositCollateralAndMintDSC {
        address spender = address(engine);
        uint256 currentAllowance = 0;
        uint256 value = maxBorrowableDSC;
        bytes memory expectedError =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, currentAllowance, value);
        vm.expectRevert(expectedError);
        vm.prank(USER);
        engine.burnDSC(maxBorrowableDSC);
    }

    function test_ApproveEngineToBurnDSC() external depositCollateralAndMintDSC {
        (uint256 dscMintedBeforeBurn,) = engine.getAccountInfo(USER);
        vm.startPrank(USER);
        dsc.approve(address(engine), maxBorrowableDSC);
        engine.burnDSC(maxBorrowableDSC);
        vm.stopPrank();

        (uint256 dscMintedAfterBurn,) = engine.getAccountInfo(USER);
        assertEq(dscMintedBeforeBurn, dscMintedAfterBurn + maxBorrowableDSC);
    }
    /*//////////////////////////////////////////////////////////////
                           REDEEM AND BURNDSC
    //////////////////////////////////////////////////////////////*/

    function test_Revert_WhenRedeemCollateralAndBurnDSCForAll() external depositCollateralAndMintDSC {
        (uint256 dscMintedBeforeRedemptionAndBurn,) = engine.getAccountInfo(USER);
        vm.startPrank(USER);
        dsc.approve(address(engine), maxBorrowableDSC);
        engine.redeemCollateralForDSC(weth, INITIAL_VALUE, maxBorrowableDSC);
        vm.stopPrank();
        (uint256 dscMintedAfterRedemptionAndBurn,) = engine.getAccountInfo(USER);

        assertEq(dscMintedBeforeRedemptionAndBurn - maxBorrowableDSC, dscMintedAfterRedemptionAndBurn);
    }

    function test_Revert_OnFullCollateralRedemptionAndDSCBurn() external depositCollateralAndMintDSC {
        vm.prank(USER);
        dsc.approve(address(engine), maxBorrowableDSC);

        uint256 collateralAmountAfterRedemption = 0;
        uint256 dscAfterRedemption = maxBorrowableDSC - (maxBorrowableDSC - 1);
        uint256 healthFactor = engine.calculateHealthFactor(dscAfterRedemption, collateralAmountAfterRedemption);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, USER, healthFactor));
        engine.redeemCollateralForDSC(weth, INITIAL_VALUE, maxBorrowableDSC - 1);
    }

    /*//////////////////////////////////////////////////////////////
                               LIQUIDATE
    //////////////////////////////////////////////////////////////*/
    function testETHCollateralPriceTanks() external depositCollateralAndMintDSC {
        uint256 collateralUSDValueBeforePriceTanks = engine.getAccountCollateralValue(USER);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(NEW_ETH_PRICE);
        uint256 collateralUSDValueAfterPriceTanks = engine.getAccountCollateralValue(USER);

        assertLt(collateralUSDValueAfterPriceTanks, collateralUSDValueBeforePriceTanks, "Collateral value tanked");

        uint256 hf = engine.getHealthFactor(USER);
        assertLt(hf, engine.getMinHealthFactor(), "Health factor should be broken");
    }

    function testLiquidateAfterPriceTanks() external {
        //User has deposited collateral - 10 ether, price => 20Ke18 USD, maxBorrowDSC = 10ke18, let user borrows = 7k18

        uint256 amountToMintByUser = maxBorrowableDSC - 3000e18;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, amountToMintByUser);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(NEW_ETH_PRICE);

        //User's position become bad
        //User's deposited collateral = 10 ether, price => 10ke18 USD, maxBorrowDSC = 5ke18, DSC to recover = 7ke18.
        //CollateralToRecoverWorth - 7k18 + 10%bonus collateral.
        uint256 hf = engine.getHealthFactor(USER);
        assertLt(hf, engine.getMinHealthFactor(), "Health factor should be broken");
        //Prepare liquidator to liquidate the collateral of user USER.
        (uint256 dscToCover,) = engine.getAccountInfo(USER);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, 2 * INITIAL_ALLOWANCE);
        ERC20Mock(weth).approve(address(engine), 2 * INITIAL_ALLOWANCE);

        dsc.approve(address(engine), dscToCover);
        engine.depositCollateralAndMintDSC(weth, 2 * INITIAL_VALUE, maxBorrowableDSC - 1e18);
        vm.stopPrank();

        uint256 hf2 = engine.getHealthFactor(LIQUIDATOR);
        assertGt(hf2, engine.getMinHealthFactor(), "Health factor should be broken");

        uint256 liquidatorCollateralBeforeLiquidate = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        vm.prank(LIQUIDATOR);
        engine.liquidate(weth, USER, dscToCover);
        uint256 ethToRecover = engine.getTokenAmountFromUsd(weth, dscToCover);
        uint256 bonusCollateral = ethToRecover * engine.getLiquidationBonus() / engine.getLiquidationPrecision();

        uint256 expectedCollateralOfLiquidator = ethToRecover + bonusCollateral;
        uint256 liquidatorCollateralAfterLiquidate = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        assertEq(
            liquidatorCollateralBeforeLiquidate + expectedCollateralOfLiquidator, liquidatorCollateralAfterLiquidate
        );
        assertGt(engine.getHealthFactor(USER), hf);
    }

    function test_Revert_IfHealthFactorOfLiquidatorBreaks() external {
        uint256 amountToMintByUser = maxBorrowableDSC - 3000e18; //7ke18
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, amountToMintByUser);
        vm.stopPrank();

        (uint256 dscToCover,) = engine.getAccountInfo(USER);
        uint256 dscMintedByLiquidator = maxBorrowableDSC - 2000e18; //8ke18
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, INITIAL_ALLOWANCE);
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        dsc.approve(address(engine), dscToCover);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, dscMintedByLiquidator);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(NEW_ETH_PRICE);

        uint256 hf = engine.getHealthFactor(USER);
        assertLt(hf, engine.getMinHealthFactor(), "Health factor should be broken");

        uint256 hfLiquid = engine.getHealthFactor(LIQUIDATOR);
        assertLt(hfLiquid, engine.getMinHealthFactor(), "Health factor should be broken");

        uint healthFactorLiquidator = engine.getHealthFactor(LIQUIDATOR);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, LIQUIDATOR, healthFactorLiquidator));
        vm.prank(LIQUIDATOR);
        engine.liquidate(weth, USER, dscToCover);
    }
}
