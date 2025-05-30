// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

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
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(address user, uint256 healthFactor);
    error DSCEngine__DSCMintingFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved(uint256 startingHealthFactor, uint256 endingHealthFactor);
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized (1/LT)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //means a bonus of 10%
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
    event DSCBurned(address indexed user, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed collateralToken, uint256 amount
    );

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
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit for minting DSC
     * @param dscToMint the amount of DSC to mint
     * @notice This function will deposit your collateral and mint your DSC in one transaction
     */
    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 dscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(dscToMint);
    }

    /**
     * @notice Follows CEI - Check, effects, interaction pattern
     * @param tokenCollateralAddress  The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        //Interaction
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }
    /**
     * Follows CEI
     * @param dscToMint - the amount of decentralized stable coin (DSC) to mint
     * @notice They must have more collateral value than the minimum threshold
     */

    function mintDSC(uint256 dscToMint) public moreThanZero(dscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += dscToMint;
        //Health checkup
        _revertIfHealthFactorIsBroken(msg.sender);
        //Interactions
        bool minted = i_dsc.mint(msg.sender, dscToMint);
        if (!minted) revert DSCEngine__DSCMintingFailed();
        emit DSCMinted(msg.sender, dscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the deposited collateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param dscToBurn The amount of dsc to burn
     * @notice This functions burns collateral and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 dscToBurn)
        external
    {
        burnDSC(dscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeem collateral already checks health factor
    }

    /**
     * @notice to redeem collateral the health factor must be above 1 AFTER collateral pulled
     * @param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral the amount of collateral to pull
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        //revert if health factor goes less than 1
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 dscToBurn) public moreThanZero(dscToBurn) nonReentrant {
        _burnDSC(dscToBurn, msg.sender, msg.sender);
        emit DSCBurned(msg.sender, dscToBurn);
    }

    /**
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the user's health factor
     * @notice You can partially liquidate a user
     * @notice You will get liquidation bonus for taking users funds.
     * @notice this function working assumes that the is protocol will be roughly 200% over collateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized then we wouldn't be able to incentivize the liquidators.
     * i.e if the price of the collateral plummeted before anyone could be liquidated.
     * @notice Follows CEI : Checks, Effects, Interaction
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(collateral)
        nonReentrant
    {
        // Check the health factor of the user.
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorOk();

        (uint256 totalDebt, uint256 totalCollateralValue) = _getAccountInformation(user);

        // Calculate MAX debt that can be covered (considering threshold)
        uint256 maxDebtByCollateral = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Apply both caps: collateral-based limit AND actual debt
        debtToCover = debtToCover > maxDebtByCollateral ? maxDebtByCollateral : debtToCover;
        debtToCover = debtToCover > totalDebt ? totalDebt : debtToCover;

        //Calculate collateral to remove (in USD terms)
        uint256 totalCollateralToRedeem = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = totalCollateralToRedeem * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        totalCollateralToRedeem += bonusCollateral;

        //Calculate MAX collateral value that can be removed (threshold-aware)
        uint256 maxAllowedTokensToRemove =
            getTokenAmountFromUsd(collateral, (debtToCover * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD);

        uint256 totalCollateralDeposited = s_collateralDeposited[user][collateral];

        totalCollateralToRedeem =
            totalCollateralToRedeem > maxAllowedTokensToRemove ? maxAllowedTokensToRemove : totalCollateralToRedeem;
        totalCollateralToRedeem =
            totalCollateralToRedeem > totalCollateralDeposited ? totalCollateralDeposited : totalCollateralToRedeem;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved(startingUserHealthFactor, endingUserHealthFactor);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE AND INTERNAL VIEW FUNCTION
    //////////////////////////////////////////////////////////////*/
    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);
        return _calculatedHealthFactor(totalDscMinted, totalCollateralValueInUSD);
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
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorBroken(user, userHealthFactor);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }
    /**
     * @dev Low level internal function, do not call unless the function calling it is checking for
     * health factor
     */

    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        console.log("amountDscToBurn: ", amountDscToBurn);
        console.log("DSC Owned: ", i_dsc.balanceOf(dscFrom));
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        console.log("Burning here with amount: ", amountDscToBurn);
        i_dsc.burn(amountDscToBurn);
        console.log("Done Burning tokens");
    }

    function _calculatedHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = collateralValueInUSD * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return collateralAdjustedForThreshold * PRECISION / totalDSCMinted;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC/EXTERNAL VIEW FUNCTION
    //////////////////////////////////////////////////////////////*/
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 answer,,,) = dataFeed.staleCheckLatestRoundData();
        uint256 price = uint256(answer) * ADDITION_FEED_PRECISION;

        return (PRECISION * usdAmountInWei / price);
    }

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
        (, int256 answer,,,) = dataFeed.staleCheckLatestRoundData();
        uint256 price = uint256(answer) * ADDITION_FEED_PRECISION;
        return amount * price / PRECISION;
    }

    function getAccountInfo(address user) external view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getCollateralDeposited(address user, address collateral) public view returns (uint256) {
        return s_collateralDeposited[user][collateral];
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalMintedDSC, uint256 collateralValueInUSD)
        external
        pure
        returns (uint256)
    {
        return _calculatedHealthFactor(totalMintedDSC, collateralValueInUSD);
    }

    function getPriceFeeds(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }
}
