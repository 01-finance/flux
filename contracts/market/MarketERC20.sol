// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity ^0.6.8;

import "./Market.sol";
import "./IMarket.sol";
import "./Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MarketERC777 是 Flux 协议中用于封装 ERC20 的标的资产合约借贷市场
 * @author Flux
 */
contract MarketERC20 is Market, IMarketERC20 {
    /**
     @notice 取款（兑换标的资产）
     @param ctokens 待用于兑换标的资产数量
     */
    function redeem(uint256 ctokens) external override {
        _redeem(msg.sender, msg.sender, ctokens, true);
    }

    function borrow(uint256 ctokens) external override {
        _borrow(msg.sender, ctokens);
    }

    function underlyingTransferIn(address sender, uint256 amount) internal virtual override returns (uint256) {
        underlying.safeTransferFrom(sender, address(this), amount);
        return amount;
    }

    function underlyingTransferOut(address receipt, uint256 amount) internal virtual override returns (uint256) {
        //  skip transfer to myself
        if (receipt == address(this)) {
            return amount;
        }
        underlying.safeTransfer(receipt, amount);
        return amount;
    }

    function repay(uint256 amount) external override {
        _repay(msg.sender, amount);
    }

    function mint(uint256 amount) external override {
        _supply(msg.sender, amount);
    }

    function depositFor(address receiver, uint256 amount) external {
        _supply(receiver, amount);
    }

    function withdraw(address to, uint256 ctokens) external {
        require(to != address(0), "address is empty");
        _redeem(msg.sender, to, ctokens, true);
    }
}
