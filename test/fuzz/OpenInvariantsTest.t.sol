// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity ^0.8.19;
// //Have our invariants aka properties that hold true for all the time

// //What are the invariants?

// //1. The total supply of DSC should be less than the total value of collateral.
// //2. Getter view functions should never revert <- evergreen invariant
// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DSCEngine engine;
//     DecentralizedStablecoin dsc;
//     address[] tokens;
//     address weth;
//     address wbtc;
//     address[] feeds;

//     function setUp() external {
//         DeployDSC deployer = new DeployDSC();
//         (dsc, engine, tokens, feeds) = deployer.run();
//         weth = tokens[0];
//         wbtc = tokens[1];
//         targetContract(address(engine));
//         excludeSender(address(this));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalDSCSupply = dsc.totalSupply();

//         uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(engine));
//         uint256 totalWBTCDeposited = IERC20(wbtc).balanceOf(address(engine));

//         uint256 wethValueInUSD = engine.getTokenUSDValue(address(weth), totalWETHDeposited);
//         uint256 wbtcValueInUSD = engine.getTokenUSDValue(address(wbtc), totalWBTCDeposited);

//         assert(wethValueInUSD + wbtcValueInUSD >= totalDSCSupply);
//     }
// }
