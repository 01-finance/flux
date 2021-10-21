// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

interface IMarketERC20 {
    function redeem(uint256 ctokens) external;

    function borrow(uint256 ctokens) external;

    function repay(uint256 amount) external;

    function mint(uint256 amount) external;
}

interface IMarketPayable {
    function redeem(uint256 ctokens) external;

    function borrow(uint256 ctokens) external;

    function repay() external payable;

    function mint() external payable;
}
