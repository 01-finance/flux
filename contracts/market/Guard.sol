// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../lib/EnumerableSet.sol";
import "../lib/Exponential.sol";
import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";
import "../lib/PubContract.sol";

import "../FluxApp.sol";
import "./Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IMargingCallMarket {
    function liquidate(
        address liquidator,
        address borrower,
        address feeCollector,
        uint256 feeRate
    ) external returns (bool ok);

    function liquidatePrepare(address borrower)
        external
        returns (
            IERC20 asset,
            uint256 ftokens,
            uint256 borrow
        );

    function killLoan(address borrower) external returns (uint256 supplies, uint256 borrows);

    function borrowBalanceOf(address acct) external view returns (uint256);

    function underlying() external view returns (IERC20);

    function repay(uint256 amount) external;
}

contract GuardStorage {
    FluxApp public flux;
    address public router; //unused address,keep for Conflux FLUX.
    mapping(IERC20 => uint256) public totalReserverForMaringCall;
}

/**
 @title 市场护卫
 */
contract Guard is Ownable, Initializable, GuardStorage {
    string private constant CONFIG_LIQUIDITY_RATE = "MKT_LIQUIDATION_FEE_RATE";
    using SafeMath for uint256;
    using Exponential for Exp;
    using SafeERC20 for IERC20;

    struct ValuesVars {
        address user;
        uint256 supplyValueMan;
        uint256 borrowValueMan;
        uint256 borrowLimitMan;
        IMarket m;
    }

    function initialize(address admin, FluxApp _flux) external initializer {
        flux = _flux;

        initOwner(admin);
    }

    /**
      @dev 穿仓清算
      1. 没收抵押资产到清算合约，
      2. 清算合约将借款资产（合约已有持仓）直接偿还到借款池。
      3. 如果清算合约的资产不足以偿还借款，则添加待还记录，等待余额充足时继续偿还，不影响本次清算。
     */
    function margincall(address borrower) external {
        require(borrower != address(0), "BORROWER_IS_EMPTY");
        require(borrower != address(this), "DISABLE_KILL_GUARD");
        ValuesVars memory vars;
        vars.user = borrower;
        FluxApp app = flux; //save gas

        require(app.killAllowed(borrower), "BORROWER_IS_FINAL");
        //没收抵押资产并转移借款到Guard
        uint256 mktCount = app.getAcctJoinedMktCount(borrower);
        IMargingCallMarket[] memory list = new IMargingCallMarket[](mktCount);
        for (uint256 i = 0; i < mktCount; i++) {
            (IMarket m, ) = app.getJoinedMktInfoAt(vars.user, i);
            list[i] = IMargingCallMarket(address(m));
        }
        for (uint256 i = 0; i < mktCount; i++) {
            IMargingCallMarket mkt = list[i];

            mkt.killLoan(borrower);
            // (uint256 supply, uint256 borrow) = mkt.killLoan(borrower);
            // if (borrow > 0 || supply > 0) {
            //     _tryToRepay(mkt);
            // }
        }
    }

    function tryToRepay(IMargingCallMarket mkt) external {
        require(flux.mktExist(IMarket(address(mkt))), "MARKET_NOT_FOUND");
        _tryToRepay(mkt);
    }

    function _tryToRepay(IMargingCallMarket mkt) private {
        address myself = address(this);
        uint256 borrows = mkt.borrowBalanceOf(myself);
        if (borrows == 0) {
            return;
        }
        IERC20 token = mkt.underlying();
        uint256 balance = token.balanceOf(myself);
        uint256 canBorrow = borrows > balance ? balance : borrows;
        if (canBorrow > 0) {
            token.approve(address(mkt), canBorrow);
            mkt.repay(canBorrow);
        }
    }

    function withdraw(IERC20 token, uint256 amount) external onlyOwner {
        require(token.transfer(msg.sender, amount), "TOKEN_TRANSFER_FAILED");
    }

    /* solhint-enable */

    /**
      @notice 清算借款人资产
      @dev 当借款人的抵押资产不足以支撑借款时，任意人可以清算该资产，帮助借款人偿还借款而清算人可获得抵押资产
      note:
       1. 当抵押率低于 < 106% 时，清算人无法获利(默认有6%的手续费)
       2. 清算人需要先授权 Guard 操作token
     */
    function liquidate(address borrower) external {
        FluxApp app = flux; //save gas
        require(borrower != address(0), "BORROWER_IS_EMPTY");
        require(borrower != address(this), "DISABLE_LIQUIDATE_GUARD");
        require(borrower != msg.sender, "LIQUIDATE_DISABLE_YOURSELF");

        require(app.liquidateAllowed(borrower), "LIQUIDATE_BORROWER_IS_FINAL");

        //没收抵押资产并转移借款到Guard
        uint256 mktCount = app.getAcctJoinedMktCount(borrower);
        IMargingCallMarket[] memory list = new IMargingCallMarket[](mktCount);
        for (uint256 i = 0; i < mktCount; i++) {
            (IMarket m, ) = app.getJoinedMktInfoAt(borrower, i);
            list[i] = IMargingCallMarket(address(m));
        }
        address myself = address(this);
        uint256 feeRate = app.configs(CONFIG_LIQUIDITY_RATE);
        address collector = app.getFluxTeamIncomeAddress();
        for (uint256 i = 0; i < mktCount; i++) {
            IMargingCallMarket mkt = list[i];

            (IERC20 underlying, uint256 ftokens, uint256 userBorrows) = mkt.liquidatePrepare(borrower);

            if (ftokens == 0 && userBorrows == 0) {
                continue;
            }
            //转移待还资产
            if (userBorrows > 0) {
                underlying.safeTransferFrom(msg.sender, address(this), userBorrows);
                if (underlying.allowance(myself, address(mkt)) < userBorrows) {
                    underlying.safeApprove(address(mkt), type(uint256).max);
                }
            }
            require(mkt.liquidate(msg.sender, borrower, collector, feeRate), "LIQUIDATE_FAILED");
        }
    }
}
