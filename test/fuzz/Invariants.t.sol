// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;
//Have our invariants aka properties that hold true for all the time

//What are the invariants?

//1. The total supply of DSC should be less than the total value of collateral.
//2. Getter view functions should never revert <- evergreen invariant
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DSCEngine engine;
    DecentralizedStablecoin dsc;
    address[] tokens;
    address weth;
    address wbtc;
    address[] feeds;
    Handler handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, tokens, feeds) = deployer.run();
        weth = tokens[0];
        wbtc = tokens[1];
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalDSCSupply() public view {
        uint256 totalDSCSupply = dsc.totalSupply();

        uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWBTCDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValueInUSD = engine.getTokenUSDValue(address(weth), totalWETHDeposited);
        uint256 wbtcValueInUSD = engine.getTokenUSDValue(address(wbtc), totalWBTCDeposited);

        console.log("WETH Value: ", wethValueInUSD);
        console.log("WBTC Value: ", wbtcValueInUSD);
        console.log("Total Supply: ", totalDSCSupply);
        console.log("Times DSC called: ", handler.timesMintIsCalled());
        console.log("Times Redeem called: ", handler.timeRedeemCalled());

        assert(wethValueInUSD + wbtcValueInUSD >= totalDSCSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getPrecision();
        engine.getHealthFactor(msg.sender);
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getCollateralTokens();
        engine.getAccountInfo(msg.sender);
        engine.getCollateralDeposited(msg.sender, weth);
        engine.getCollateralDeposited(msg.sender, wbtc);
        engine.getAccountCollateralValue(msg.sender);
    }
}
