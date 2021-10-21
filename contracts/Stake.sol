// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./lib/Ownable.sol";
import { IMarketERC20, IMarketPayable } from "./market/IMarket.sol";

interface IStakePoolManager {
    function beforeStake(address user) external;

    function beforeUnStake(address user) external;

    function supportTokens(address token) external returns (address market);
}

interface ILPToken is IERC20 {
    function redeem(uint256 redeemTokens) external returns (uint256);

    function decimals() external returns (uint8);
}

library SafeLP {
    function safeRedeem(ILPToken lp, uint256 redeemTokens) internal {
        uint256 result = lp.redeem(redeemTokens);
        require(result == 0, "redeem must return zero");
    }
}

contract VTokenProxy {
    using SafeERC20 for IERC20;
    using SafeLP for ILPToken;

    function withdraw(ILPToken vToken, uint256 amount) external {
        IERC20(address(vToken)).safeTransferFrom(msg.sender, address(this), amount);
        vToken.safeRedeem(amount);
        uint256 balanceThis = address(this).balance;
        // require(balanceThis >= amount, "incorrect balance");
        require(balanceThis > 0, "balance is zero");
        StakePool(msg.sender).vproxyReceive{ value: balanceThis }();
    }

    receive() external payable {}
}

/**
  @title 抵押池
  @dev 任何地址可以将指定的 LP Token 抵押到本抵押池，在每个抵押周期内尚未停止前可以赎回抵押的LP。
  但当抵押停止后，不可赎回。在抵押停止期Flux将 LP Token 兑换成底层原始资产后将其存入到 FLUX 借贷池，
  抵押者可获得相应的抵押池ftoken。
 */
contract StakePool is Initializable, Ownable, ERC20Snapshot {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeLP for ILPToken;

    IStakePoolManager public fluxApp;
    ILPToken public lpToken;
    IERC20 public underlyingToken0;
    IERC20 public underlyingToken1;
    bool public isNativeWToken;
    uint256 public totalStake;
    uint256 public lastSnapshotId;
    uint256 public currentStakeEndTime;
    VTokenProxy public vproxy;

    ///@dev 记录每次抵押后 LP token 兑换成原始资产后，将原始资产存入到FLUX借贷池时获得的ftokens数量
    // key=snapshotId,value=[underlyingToken0 ftokens,underlyingToken1 ftokens]
    mapping(uint256 => uint256[2]) public ftokensAt;
    ///@dev 记录已领取记录
    /// key=用户地址， value= snapshotId
    mapping(address => uint256) public lastClaimedAt;

    bool public stakeStopped;

    event Rebase(uint256 id, uint256 amount0, uint256 amount1);
    event Claimed(address indexed staker, uint256 start, uint256 end, uint256 stakeAmount, uint256 amount0, uint256 amount1);
    /// @dev 打劫LP成功
    event LPRobbed(address underlying, address market, uint256 input, uint256 output);

    constructor() public ERC20("FluxStakePoolImpl", "fPoolImpl") {}

    function initialize(
        address admin,
        IStakePoolManager _fluxApp,
        ILPToken _token,
        bool _isNativeWToken,
        IERC20 _underlyingToken0,
        IERC20 _underlyingToken1,
        VTokenProxy _vproxy
    ) external initializer {
        initOwner(admin);

        fluxApp = _fluxApp;
        lpToken = _token;
        underlyingToken0 = _underlyingToken0;
        underlyingToken1 = _underlyingToken1;
        if (_isNativeWToken) {
            require(address(_vproxy) != address(0), "VPROXY_IS_EMPTY");
            // 如果 underlyingToken0 是 Coin(如 ETH,CFX,BNB)，则需要通过一个代理实现 transfer，
            // 因为 Stake合约是通过代理部署，eth.transfer(amount) 的 Gas 有限，转账给代理合约时，交易将失败。
            // 因此 将 LP Token 兑换成原始标的时需通过中间合约提现
            isNativeWToken = _isNativeWToken;
            vproxy = _vproxy;
            IERC20(_token).safeApprove(address(vproxy), type(uint256).max);
        }
        _setupDecimals(_token.decimals());
    }

    function setVProxy(VTokenProxy _vproxy) external onlyOwner {
        require(address(_vproxy) != address(0), "VPROXY_IS_EMPTY");
        // 如果 underlyingToken0 是 Coin(如 ETH,CFX,BNB)，则需要通过一个代理实现 transfer，
        // 因为 Stake合约是通过代理部署，eth.transfer(amount) 的 Gas 有限，转账给代理合约时，交易将失败。
        // 因此 将 LP Token 兑换成原始标的时需通过中间合约提现
        isNativeWToken = true;
        vproxy = _vproxy;
        IERC20(lpToken).safeApprove(address(vproxy), type(uint256).max);
    }

    function getCurrentStaked(address staker) public view returns (uint256 amount) {
        uint256 last = lastSnapshotId;
        if (last == 0) {
            amount = balanceOf(staker);
        } else {
            amount = balanceOf(staker).sub(balanceOfAt(staker, last));
        }
    }

    /**
       @notice 查询在指定轮次的抵押数量
       @param staker 抵押账户
       @param snapID 从 1 开始的抵押轮次, type(uint256).max 表示查询当前抵押量
     */
    function stakeAmountAt(address staker, uint256 snapID) public view returns (uint256 amount) {
        if (snapID == type(uint256).max) {
            return getCurrentStaked(staker);
        }
        uint256 last = lastSnapshotId;
        require(snapID > 0 && snapID <= last, "SNAPID_NONEXISTENT");
        uint256 preStaked = snapID == 1 ? 0 : balanceOfAt(staker, snapID - 1);
        uint256 staked = balanceOfAt(staker, snapID);
        amount = staked.sub(preStaked);
    }

    function getCurrentTotalStaked() public view returns (uint256 amount) {
        uint256 last = lastSnapshotId;
        if (last == 0) {
            amount = totalSupply();
        } else {
            amount = totalSupply().sub(totalSupplyAt(last));
        }
    }

    /**
      @notice 查询指定轮次抵押数量
     */
    function totalStakeAt(uint256 snapID) public view returns (uint256 amount) {
        if (snapID == type(uint256).max) {
            return getCurrentTotalStaked();
        }
        uint256 last = lastSnapshotId;
        require(snapID > 0 && snapID <= last, "SNAPID_NONEXISTENT");
        uint256 preStaked = snapID == 1 ? 0 : totalSupplyAt(snapID - 1);
        uint256 staked = totalSupplyAt(snapID);
        amount = staked.sub(preStaked);
    }

    function _transfer(
        address,
        address,
        uint256
    ) internal override {
        revert("DISABLE_TRANSFER");
    }

    function unStake(uint256 amount) external {
        require(!stakeStopped, "UNSTAKE_STOPPED");

        address staker = msg.sender;
        fluxApp.beforeUnStake(staker);

        require(getCurrentStaked(staker) >= amount, "UNSTAKE_BLANCE_EXCEEDS");
        _burn(staker, amount);
        totalStake = totalStake.sub(amount);

        IERC20(address(lpToken)).safeTransfer(staker, amount);
    }

    function stake(uint256 amount) external {
        require(!stakeStopped, "STAKE_STOPPED");
        address staker = msg.sender;
        fluxApp.beforeStake(staker);

        IERC20(address(lpToken)).safeTransferFrom(staker, address(this), amount);
        _mint(staker, amount);
        totalStake = totalStake.add(amount);
    }

    function resetEndTime(uint256 end) external onlyOwner {
        require(end > block.timestamp, "INVLIAD_INPUT");
        currentStakeEndTime = end;
    }

    function setStakeStaus(bool stop) external onlyOwner {
        stakeStopped = stop;
    }

    /**
      @notice 结束当前抵押，并开启下一次抵押
      @dev 结束时将本次抵押资产全部赎回到以太坊
     */
    function rebase() external onlyOwner {
        require(!stakeStopped, "STAKE_HAS_STOPPED"); //防止 rebase 被错误触发

        stakeStopped = true; //将停止抵押

        IERC20 token0 = underlyingToken0;
        IERC20 token1 = underlyingToken1;

        // 非可打劫的LP池，不可重置
        require(address(token0) != address(0), "DISABLE_REBASE");
        require(currentStakeEndTime < block.timestamp, "NOT_YET");

        ILPToken lp = lpToken;
        uint256 balance = IERC20(address(lp)).balanceOf(address(this));
        if (balance > 0) {
            if (isNativeWToken) {
                vproxy.withdraw(lp, balance);
            } else {
                lp.safeRedeem(balance);
            }
        }
        uint256 last = _snapshot();
        lastSnapshotId = last;

        uint256 amount0;
        uint256 amount1;
        amount0 = _supplyUnderlying(last, token0, true);
        if (address(token1) != address(0)) {
            amount1 = _supplyUnderlying(last, token1, false);
        }
        emit Rebase(last, amount0, amount1);
    }

    function vproxyReceive() external payable {
        require(msg.sender == address(vproxy), "only VProxy");
    }

    function unclaimedFTokens(address staker)
        public
        view
        returns (
            uint256 start,
            uint256 end,
            uint256 stakeAmount,
            uint256 amount0,
            uint256 amount1
        )
    {
        start = lastClaimedAt[staker] + 1;
        end = lastSnapshotId;
        // TODO: 可以优化已获得更高查询效率
        // 第一次参与抵押时，将不得不遍历所有轮次。
        for (uint256 i = start; i <= end; i++) {
            (uint256 locked, uint256 a0, uint256 a1) = canCalimedFTokens(staker, i);
            amount0 = amount0.add(a0);
            amount1 = amount1.add(a1);
            stakeAmount = stakeAmount.add(locked);
        }
    }

    /**
      @notice 抵押人可随时获取已置换后的ftoken,不可重复领取
     */
    function claim(address staker) external {
        require(staker != address(0), "STAKER_IS_EMPTY");
        (uint256 start, uint256 end, uint256 stakeAmount, uint256 amount0, uint256 amount1) = unclaimedFTokens(staker);
        require(lastClaimedAt[staker] != end, "REPEAT_CLAIM");
        require(stakeAmount > 0, "STAKED_IS_ZERO");
        require(amount0 > 0, "CLAIM_FTOKEN_IS_ZERO");

        lastClaimedAt[staker] = end;
        if (amount0 > 0) {
            IERC20 mkt = IERC20(fluxApp.supportTokens(address(underlyingToken0)));
            require(mkt.transfer(staker, amount0), "TRANSFER_FTOKEN_FAILED");
        }
        if (amount1 > 0) {
            IERC20 mkt = IERC20(fluxApp.supportTokens(address(underlyingToken1)));
            require(mkt.transfer(staker, amount1), "TRANSFER_FTOKEN_FAILED");
        }
        emit Claimed(staker, start, end, stakeAmount, amount0, amount1);
    }

    /**
      @notice 查询每个抵押周期内可领取的 Ftoken 数量
      @param staker 待查询账户
      @param snapID 轮次
      @return locked 该轮次的抵押数量
      @return amount0 可以得到Underlying0资产数量
      @return amount1 可以得到Underlying1资产数量
     */
    function canCalimedFTokens(address staker, uint256 snapID)
        public
        view
        returns (
            uint256 locked,
            uint256 amount0,
            uint256 amount1
        )
    {
        locked = stakeAmountAt(staker, snapID);
        if (locked == 0) {
            return (0, 0, 0);
        }
        uint256 ftokens0 = ftokensAt[snapID][0];
        uint256 ftokens1 = ftokensAt[snapID][1];
        uint256 total = totalStakeAt(snapID); //不会为零

        amount0 = ftokens0.mul(locked).div(total);
        amount1 = ftokens1.mul(locked).div(total);
    }

    function _supplyUnderlying(
        uint256 snapID,
        IERC20 underlying,
        bool isToken0
    ) private returns (uint256) {
        uint256 balance = isNativeWToken ? address(this).balance : underlying.balanceOf(address(this));
        address mkt = fluxApp.supportTokens(address(underlying));
        require(mkt != address(0), "MARKET_NOT_FOUND");
        uint256 ftokenAmount;
        if (balance > 0) {
            // transfer as supply
            uint256 fTokenBalanceBefore = IERC20(mkt).balanceOf(address(this));
            if (isNativeWToken) {
                IMarketPayable(mkt).mint{ value: balance }();
            } else {
                uint256 allowanceBalance = underlying.allowance(address(this), mkt);
                if (allowanceBalance == 0) {
                    underlying.safeApprove(mkt, type(uint256).max);
                } else if (allowanceBalance < balance) {
                    underlying.safeIncreaseAllowance(mkt, balance);
                }
                IMarketERC20(mkt).mint(balance);
            }
            uint256 fTokenBalanceNow = IERC20(mkt).balanceOf(address(this));
            ftokenAmount = fTokenBalanceNow.sub(fTokenBalanceBefore, "SUPPLY_OVERFLOW");
            require(ftokenAmount > 0, "FTOKENS_IS_ZERO");
            //storage
            uint256 index = isToken0 ? 0 : 1;
            uint256 curr = ftokensAt[snapID][index];
            ftokensAt[snapID][index] = curr.add(ftokenAmount);
        }
        emit LPRobbed(address(underlying), mkt, balance, ftokenAmount);
        return balance;
    }
}
