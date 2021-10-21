// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;
import "../lib/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract bcFLUXSwap is Ownable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = 0x523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c; //Keccak-256(OPERATOR)
    IERC20 public bcFLUX;
    IERC20 public bFLUX;

    constructor(address _bcFLUX, address _bFLUX) public {
        require(_bcFLUX != address(0), "bcFLUX is empty");
        require(_bFLUX != address(0), "bcFLUX1 is empty");

        bcFLUX = IERC20(_bcFLUX);
        bFLUX = IERC20(_bFLUX);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function swap(uint256 amount) external {
        require(amount > 0, "swap amount is zero");

        IERC20 _bFLUX = bFLUX;
        uint256 balance = _bFLUX.balanceOf(address(this));
        require(balance >= amount, "insufficient liquidity");

        bcFLUX.safeTransferFrom(msg.sender, address(this), amount);
        _bFLUX.safeTransfer(msg.sender, amount);
    }

    function removeBCFLUX() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "sender must be an operator");
        bcFLUX.safeTransfer(msg.sender, bcFLUX.balanceOf(address(this)));
    }

    function removeBFLUX() external {
        withdrawAny(bFLUX);
    }

    function withdrawAny(IERC20 token) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "sender must be an admin");
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }
}
