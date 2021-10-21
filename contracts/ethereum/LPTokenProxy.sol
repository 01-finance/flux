// SPDX-License-Identifier: MIT
// Created by Flux Team
pragma solidity 0.6.8;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/Ownable.sol";

interface ICompoundCToken {
    function underlying() external returns (address);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);
}

interface IAAVEILendingPool {
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
  @dev Flux 部署在Conflux上的 LP Token 管理合约，负责赎回LPToken并充值到 Conflux Flux 抵押池。
 */
contract LPTokenProxy is Ownable {
    // compound ether cETH 合约地址
    address private constant COMPOUND_ETHER = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    // aave 抵押池合约地址
    address public constant AAVE_LENDINGPOOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    /**
      @notice 兑换所有 Compound ETH LP Token，并转账给固定接受者
     */
    function withdrawCompundETH(address payable fluxPool) external onlyOwner {
        require(fluxPool != address(0), "FLUXPOOL_IS_EMPTY");
        uint256 balance = address(this).balance;
        _withdrawCompoundLP(ICompoundCToken(COMPOUND_ETHER));
        uint256 balanceNow = address(this).balance;
        require(balanceNow > balance, "REDEEM_BAD");
        fluxPool.transfer(balanceNow - balance);
    }

    /**
     * @notice 兑换所有LPToken到本合约，并转账给固定接受者
     */
    function withdrawCompoundERC20LP(ICompoundCToken ctoken, address fluxPool) external onlyOwner {
        require(fluxPool != address(0), "FLUXPOOL_IS_EMPTY");
        IERC20 underlying = IERC20(ctoken.underlying());
        uint256 balance = underlying.balanceOf(address(this));
        _withdrawCompoundLP(ctoken);
        uint256 balanceNow = underlying.balanceOf(address(this));
        require(balanceNow > balance, "REDEEM_BAD");
        require(underlying.transfer(fluxPool, balanceNow - balance), "TRANSFER_FAILED");
    }

    function _withdrawCompoundLP(ICompoundCToken ctoken) private {
        uint256 ctokens = ctoken.balanceOf(address(this));
        require(ctokens > 0, "BALANCE_IS_ZERO");
        require(ctoken.redeem(ctokens) == 0, "REDEEM_FAILED");
    }

    /**
      @notice 从AAVE中提取所有资产，并转账给固定接受者
     */
    function withdrawFromAave(address asset, address fluxPool) external onlyOwner {
        require(fluxPool != address(0), "FLUXPOOL_IS_EMPTY");
        uint256 amount = IAAVEILendingPool(AAVE_LENDINGPOOL).withdraw(asset, type(uint256).max, fluxPool);
        require(amount > 0, "WITHDRAW_IS_ZERO");
    }
}
