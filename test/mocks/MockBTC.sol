// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBTC is ERC20 {
    uint256 constant INITIAL_SUPPLY = 1000000000000000000000000;
    string public constant NAME = "Wrapped Ether";
    string public constant SYMBOL = "WETH";

    constructor() ERC20(NAME, SYMBOL) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }
}
