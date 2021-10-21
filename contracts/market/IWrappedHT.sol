// SPDX-License-Identifier: MIT
// Copy from https://github.com/Conflux-Dev/WrappedConflux/blob/master/contracts/IWrappedCfx.sol
// Created by Flux Team

pragma solidity ^0.6.8;

interface IWrappedHT {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function withdraw(uint256 wad) external;

    function deposit() external payable;
}

interface INativeCoinWithdraw {
    function withdrawTo(address account, uint256 amount) external;

    function withdraw(uint256 amount) external;
}
