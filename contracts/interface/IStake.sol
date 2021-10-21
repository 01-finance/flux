// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStake is IERC20 {
    function totalStakeAt(uint256 snapID) external view returns (uint256 amount);

    function stakeAmountAt(address staker, uint256 snapID) external view returns (uint256 amount);

    function unStake(uint256 amount) external;

    function stake(uint256 amount) external;
}
