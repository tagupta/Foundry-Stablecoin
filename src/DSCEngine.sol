// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Tanu Gupta
 *
 * This system is designed to be a minimal as possible, and have the tokens maintain a 1 token == 1$ pegged.
 * This stablecoin has the following properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * This is similar to DAI if DAI had no governance, no fees and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized".
 * At NO point, should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC. as   well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowedAsCollateral();
    error DSCEngine__CollateralTransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);
    error DSCEngine__DSCMintingFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized (1/LT)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscAmountMinted) private s_DSCMinted;
    address[] private s_collateralTokens; //0 - ETH, 1 - BTC
    DecentralizedStablecoin private immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amount);
    event DSCMinted(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) revert DSCEngine__MustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) revert DSCEngine__TokenNotAllowedAsCollateral();
        _;
    }
    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dsc) {
        // USD Backed price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // ETH/USD, BTC/USD, MKR/USD...
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStablecoin(dsc);
        // i_dsc.transferOwnership(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateralAndMintDSC() external {
        // Based on the USD value of the collateral, the amount of DSC gets minted and so the mapping gets updated.
    }

    /**
     * @notice Follows CEI - Check, effects, interaction pattern
     * @param tokenCollateralAddress  The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        //Interaction
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__CollateralTransferFailed();
    }
    /**
     * Follows CEI
     * @param dscToMint - the amount of decentralized stable coin (DSC) to mint
     * @notice They must have more collateral value than the minimum threshold
     */

    function mintDSC(uint256 dscToMint) external moreThanZero(dscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += dscToMint;
        //Health checkup
        _revertIfHealthFactorIsBroken(msg.sender);
        //Interactions
        bool minted = i_dsc.mint(msg.sender, dscToMint);
        if (!minted) revert DSCEngine__DSCMintingFailed();
        emit DSCMinted(msg.sender, dscToMint);
    }

    //Burning DSC to withdraw collateral
    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    //Quick way to save from liquidation
    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
                           PRIVATE AND INTERNAL VIEW FUNCTION
    //////////////////////////////////////////////////////////////*/
    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        //Summation of all the collateral i * threshold i / all minted DSC;
        //total Dsc minted
        // total collateral value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);
        //Both the assets have the same LIQUIDATION_THRESHOLD => ab + cb = b(a + c)
        uint256 collateralAdjustedForThreshold =
            totalCollateralValueInUSD * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION / totalDscMinted);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorBroken(userHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC VIEW FUNCTION
    //////////////////////////////////////////////////////////////*/
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralInUSD) {
        // Loop through each collateral token, get the amount they have deposited and map it to the price and get the USD value
        uint256 totalTokens = s_collateralTokens.length;
        for (uint256 i = 0; i < totalTokens; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];

            //get the price of that token in USD using chainlink pricefeed
            totalCollateralInUSD += getTokenUSDValue(token, collateralAmount);
        }
        return totalCollateralInUSD;
    }

    /**
     * @param token token to get the value for
     * @param amount multiply the amount with the usd value
     */
    function getTokenUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 answer,,,) = dataFeed.latestRoundData();
        uint256 price = uint256(answer) * ADDITION_FEED_PRECISION;
        return amount * price / PRECISION;
    }

    function getCollateralTokens() public view returns(address [] memory){
        return s_collateralTokens;
    } 
}
