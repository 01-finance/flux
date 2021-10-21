// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../FluxMint.sol";

contract FluxMintFixedMock is FluxMint {
    function calcFluxsMined(uint256 fromBlock, uint256 endBlock) public pure override returns (uint256) {
        return 1e18 * (endBlock - fromBlock);
    }
}
