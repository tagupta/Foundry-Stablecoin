// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ERC20Burnable, ERC20} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
/**
 * @title Decentralized Stable coin
 * @author Tanu Gupta
 * Collateral: Exogenous (ETC and BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stable coin system.
 */
contract DecentralizedStablecoin is ERC20Burnable, Ownable{
    error DecentralizedStablecoin__MustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__NotZeroAddress();

    string constant NAME = "Decentralized Stable coin";
    string constant SYMBOL = "DSC";

    //Intial owner of this token is the DSC Engine, that'll going to govern the mechanics of this token
    constructor (address _dscEngine) ERC20(NAME,SYMBOL) Ownable(_dscEngine){  
    }

    //Override the burn function from the ERC20 burnable contract
    function burn(uint256 value) public override onlyOwner{
        uint balance = balanceOf(msg.sender);
        if(value <= 0) revert DecentralizedStablecoin__MustBeMoreThanZero();
        if(balance < value) revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        super.burn(value);
    }

    function mint(address _to, uint _amount) external onlyOwner returns(bool){
        if(_to == address(0)) revert DecentralizedStablecoin__NotZeroAddress();
        if(_amount <= 0) revert DecentralizedStablecoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }


}