// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "./Market.sol";
import "./Interface.sol";
import "./IWrappedHT.sol";
import "../lib/PubContract.sol";
import "./IMarket.sol";

contract WithdrawProxy {
    function withdrawTo(
        IWrappedHT wht,
        address to,
        uint256 amount
    ) external {
        wht.transferFrom(msg.sender, address(this), amount);
        wht.withdraw(amount);
        address payable user = address(uint160(to));
        user.transfer(amount);
    }

    receive() external payable {}
}

/**
 * @title Conflux主网币 CFX 的借贷市场
 * @author Flux
 */
contract MarketCFX is Market, IMarketPayable {
    event WithdrawProxyChanged(address oldValue, address newValue);

    function initWithdrawProxy(WithdrawProxy wp) external onlyOwner {
        emit WithdrawProxyChanged(address(withdrawProxy), address(wp));
        withdrawProxy = address(wp);
        underlying.safeApprove(withdrawProxy, type(uint256).max);
    }

    /**
     @notice 供给资产
     @dev 挖矿人通过提供 CFX 兑换新的 fCFX，失败时将回滚交易
     */
    function mint() external payable override {
        _supply(msg.sender, msg.value);
    }

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

    function repay(uint256 amount) external {
        _repay(msg.sender, amount);
    }

    function repay() external payable override {
        require(msg.value > 0, "REPAY_IS_ZERO");
        _repay(msg.sender, msg.value);
    }

    function underlyingTransferIn(address from, uint256 amount) internal override returns (uint256) {
        if (msg.value == 0) {
            // 意味着没有转入Coin，只能从Warp Coin 中转入
            underlying.safeTransferFrom(from, address(this), amount);
        } else {
            require(msg.value >= amount && amount > 0, "INVALID_UNDERLYING_TRANSFER");
            // 需要将多余的 amount 退回
            if (msg.value > amount) {
                payable(from).transfer(msg.value - amount);
            }
            //  Coin to  Warp Coin
            IWrappedHT(address(underlying)).deposit{ value: amount }();
        }
        return amount;
    }

    function underlyingTransferOut(address receipt, uint256 amount) internal override returns (uint256) {
        IERC20 underlyingToken = underlying;

        require(underlyingToken.balanceOf(address(this)) >= amount, "CASH_EXECEEDS");

        if (receipt == address(guard)) {
            // just trasfer WCFX to gurad
            underlyingToken.safeTransfer(receipt, amount);
        } else {
            // WCFX convert to CFX and withdraw to receipt
            if (withdrawProxy != address(0)) {
                IWrappedHT token = IWrappedHT(address(underlyingToken));
                WithdrawProxy(withdrawProxy).withdrawTo(token, receipt, amount);
            } else {
                // 如果没有设置代理则尝试直接通过 warp token 的  withdrawTo
                INativeCoinWithdraw(address(underlyingToken)).withdrawTo(receipt, amount);
            }
        }
        return amount;
    }

    function withdraw(address to, uint256 ctokens) external {
        require(to != address(0), "address is empty");
        _redeem(msg.sender, to, ctokens, true);
    }

    receive() external payable {
        _supply(msg.sender, msg.value);
    }
}
