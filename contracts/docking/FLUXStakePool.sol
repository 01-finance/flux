// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../lib/Ownable.sol";

interface IStakePoolCallBack {
    function beforeStake(address user) external;

    function beforeUnStake(address user) external;
}

contract FLUXStakePool is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable lpToken;//flux
    bool public enableTranferLimit;
    bool public openWithdraw;
    uint256 public lockTime;
    IStakePoolCallBack callBack;
    mapping(address => uint256) public lockBlocks;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _lockTime,
        address _flux,
        IStakePoolCallBack _callBack
    ) public ERC20(_name, _symbol) {
        lockTime = _lockTime;
        lpToken = _flux;
        enableTranferLimit = true;
        callBack = _callBack;
    }

    modifier onlyHuman {
        require(msg.sender == tx.origin);
        _;
    }

    function updateLockTime(uint256 lt) external onlyOwner {
        require(lt > 0);
        lockTime = lt;
    }

    function toggleTransferLimit(bool enable) external onlyOwner {
        enableTranferLimit = enable;
    }

    function toggleOpenWithdraw(bool open) external onlyOwner {
        openWithdraw = open;
    }

    function stake(uint256 amount) external onlyHuman {
        require(amount > 0, "zero deposit");
        callBack.beforeStake(msg.sender);

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 shares = amount;

        uint256 oldAmt = balanceOf(msg.sender);
        if (oldAmt == 0) {
            lockBlocks[msg.sender] = now.add(lockTime);
        } else {
            uint256 expireTime = lockBlocks[msg.sender];
            uint256 totalAmt = oldAmt.add(amount);
            uint256 newAmtShare = amount.mul(lockTime);
            if (expireTime > now) {
                // (oldAmt * (expireTime - now) + newAmt * lockTime) / (oldAmt + newAmt)
                uint256 deltaBlocks = expireTime.sub(now);
                uint256 avgLockTime = oldAmt.mul(deltaBlocks).add(newAmtShare).div(totalAmt);
                lockBlocks[msg.sender] = now.add(avgLockTime);
            } else {
                // newAmt * lockTime / (oldAmt + newAmt)
                uint256 avgLockTime = newAmtShare.div(totalAmt);
                lockBlocks[msg.sender] = now.add(avgLockTime);
            }
        }
        _mint(msg.sender, shares);
    }

    function unStake(uint256 _shares) public onlyHuman {
        require(_shares > 0, "shares is zero");
        if (!openWithdraw) {
            require(lockBlocks[msg.sender] < now, "locked");
        }
        callBack.beforeUnStake(msg.sender);

        _burn(msg.sender, _shares);
        IERC20(lpToken).safeTransfer(msg.sender, _shares);
    }

    function canWithdraw(address user) public view returns (bool) {
        if (openWithdraw) {
            return true;
        }
        return now > lockBlocks[user];
    }

    function _transfer(
        address,
        address,
        uint256
    ) internal override {
        require(!enableTranferLimit, "DISABLE_TRANSFER");
    }
}
