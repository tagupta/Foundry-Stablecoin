// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Vm} from "forge-std/Vm.sol";

contract DSCEngineTest is Test {
    DecentralizedStablecoin dsc;
    DSCEngine engine;
    address[] tokens;
    address[] feeds;
    address USER = makeAddr("user");
    uint256 constant INITIAL_VALUE = 10 ether;
    uint256 constant INITIAL_ALLOWANCE = 10 ether;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized (1/LT)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, tokens, feeds) = deployer.run();
        weth = tokens[0];
        ethUsdPriceFeed = feeds[0];
        btcUsdPriceFeed = feeds[1];
        ERC20Mock(weth).mint(USER, INITIAL_VALUE);
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
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, 0));
        engine.mintDSC(dscMintAmount);
    }

    function test_Revert_WhenMintedMoreThanMaxBorrowableLimit() external depositedCollateral {
        (, uint256 accountCollateralValueUSD) = engine.getAccountInfo(USER);
        uint256 maxBorrowableLimit = (accountCollateralValueUSD * LIQUIDATION_THRESHOLD) / (LIQUIDATION_PRECISION);

        uint256 healthFactor = maxBorrowableLimit * PRECISION / ((maxBorrowableLimit + 1));

        bytes memory expectedError =
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, healthFactor);
        vm.expectRevert(expectedError);
        vm.prank(USER);
        engine.mintDSC(maxBorrowableLimit + 1);
    }

    function test_MintSuccessWhenBorrowedLessThanMaxLimit() external depositedCollateral {
        (, uint256 accountCollateralValueUSD) = engine.getAccountInfo(USER);
        uint256 maxBorrowableLimit = (accountCollateralValueUSD * LIQUIDATION_THRESHOLD) / (LIQUIDATION_PRECISION);

        vm.prank(USER);
        vm.recordLogs();
        engine.mintDSC(maxBorrowableLimit - 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 dscTokenMinted,) = engine.getAccountInfo(USER);
        bytes32 signature = keccak256("DSCMinted(address,uint256)");

        assertEq(dscTokenMinted, maxBorrowableLimit - 1);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == signature) {
                console.log("Inside signature");
                address user = address(uint160(uint256(logs[i].topics[1])));
                uint256 amountMinted = uint256(bytes32(logs[i].data));
                assertEq(user, USER);
                assertEq(amountMinted, maxBorrowableLimit - 1);
            }
        }
    }
    /*//////////////////////////////////////////////////////////////
                     DEPOSITCOLLATERAL AND MINTDSC
    //////////////////////////////////////////////////////////////*/

    function test_DepositCollateralAndMintDSC() external {
        uint tokenUSDValue = engine.getTokenUSDValue(weth, INITIAL_VALUE);
        uint256 maxDSCMinted = (tokenUSDValue * LIQUIDATION_THRESHOLD) / (LIQUIDATION_PRECISION);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), INITIAL_VALUE);
        engine.depositCollateralAndMintDSC(weth, INITIAL_VALUE, maxDSCMinted);
        (uint dscMinted, uint256 accountCollateralValueUSD) = engine.getAccountInfo(USER);
        vm.stopPrank();

        assertEq(dscMinted, maxDSCMinted);
        assertEq(accountCollateralValueUSD, tokenUSDValue);
    }
}
