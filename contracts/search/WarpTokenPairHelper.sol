// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WarpTokenPairHelper {
    /**
     * @notice 获取LP所对应的底层资产数量
     */
    function getTokenAmount(address token, address user)
        external
        view
        returns (
            address token0,
            uint256 amount0,
            address token1,
            uint256 amount1
        )
    {
        token0 = token;
        amount0 = IERC20(token).balanceOf(user);
        token1 = address(0);
        amount1 = 0;
    }

    function getTokenPrice(address[] calldata) external pure returns (uint256) {
        revert("WarpTokenPair::not support");
    }
}
