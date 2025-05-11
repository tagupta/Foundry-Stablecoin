// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStablecoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 private constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;
    uint256 public timeRedeemCalled;
    address[] public usersWhoDepositedCollateral;

    constructor(DSCEngine _engine, DecentralizedStablecoin _dsc) {
        engine = _engine;
        dsc = _dsc;
        address[] memory tokens = engine.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
    }

    //deposit collateral
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        //double push can happen
        usersWhoDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralDeposited(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        vm.assume(amountCollateral != 0);

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = engine.getAccountInfo(msg.sender);
        uint256 collateralValueInUsd = engine.getTokenUSDValue(address(collateral), amountCollateral);
        uint256 healthFactor =
            engine.calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd - collateralValueInUsd);
        vm.assume(healthFactor >= engine.getMinHealthFactor());

        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        console.log("Redeem called successfully");
        timeRedeemCalled++;
        
    }

    function mintDSC(uint256 dscToMint, uint256 addressSeed) public {
        if (usersWhoDepositedCollateral.length <= 0) return;
        address sender = usersWhoDepositedCollateral[addressSeed % usersWhoDepositedCollateral.length];

        (uint256 totalDSCMinted, uint256 depositedCollateralValueUSD) = engine.getAccountInfo(sender);
        uint256 maxBorrowableDSC =
            depositedCollateralValueUSD * engine.getLiquidationThreshold() / engine.getLiquidationPrecision();

        int256 mintableDSC = int256(maxBorrowableDSC - totalDSCMinted);
        vm.assume(mintableDSC > 0);

        dscToMint = bound(dscToMint, 0, uint256(mintableDSC));
        vm.assume(dscToMint != 0);

        vm.prank(sender);
        engine.mintDSC(dscToMint);
        timesMintIsCalled++;
    }

    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
