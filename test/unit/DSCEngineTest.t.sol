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
    address ANY_COLLATERAL = makeAddr("collateral");
    uint256 constant INITIAL_VALUE = 10 ether;
    uint256 constant INITIAL_ALLOWANCE = 10 ether;
    address weth;
    address ethUsdPriceFeed;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, tokens, feeds) = deployer.run();
        weth = tokens[0];
        ethUsdPriceFeed = feeds[0];
        ERC20Mock(weth).mint(USER, INITIAL_VALUE);
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
    function test_Revert_IfCollateralZero() external {
        uint256 amountCollateral = 0;
        ERC20Mock(weth).approve(address(engine), INITIAL_ALLOWANCE);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        vm.prank(USER);
        engine.depositCollateral(weth, amountCollateral);
    }

    function testDepositCollateralIsNotAllowedForRandomAddress() external {
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector);
        vm.prank(USER);
        engine.depositCollateral(ANY_COLLATERAL, INITIAL_VALUE);
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

    function testDepositEthCollateral() external {
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
}
