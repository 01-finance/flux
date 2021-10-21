// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WithdrawToken {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    function withdraw(IERC20 token) external {
        require(msg.sender == owner, "not owner");
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}
