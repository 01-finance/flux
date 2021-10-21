// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import { StakePool } from "./Stake.sol";
import "./FluxMint.sol";
import "./market/Interface.sol";
import "./lib/EnumerableSet.sol";
import "./interface/IStake.sol";

enum MarketStatus {
    /// @notice 尚未运行
    Unknown,
    /// @notice 已开放
    Opened,
    /// @notice 已关闭
    /// @dev 属于短暂的闭市，
    Stopped
}

contract AppStroage {
    struct Market {
        /**
         * @notice 市场状态
         */
        MarketStatus status;
        /**
         * @notice  一个 FToken 的抵押率，一般在100%到190%
         * 代表账户通过铸造 cToken 获得的流动性（借款限额）的比例增加。
         * 一般来说，大额资产或流动性较强的资产抵押率较低，而小额资产或流动性较差的资产抵押率较高
         *  如果一项资产的抵押率为 0%，则不能作为抵押品（或在清算时被扣押）。
         */
        uint256 collRatioMan;
        /**
         * @notice 已进入该市场的账户
         * TODO: 提供释放借贷资产为0的记录，降低存储
         */
        mapping(address => bool) accountMembership;
    }
    ///@notice 清算抵押率
    uint256 public constant CLOSE_FACTOR_MANTISSA = 1.1 * 1e18; //110%
    ///@notice 取款时抵押率下限，如果取款导致抵押率低于此基线，将不允许取款
    uint256 public constant REDEEM_FACTOR_MANTISSA = 1.15 * 1e18; //110%
    ///@notice 单一账户可进入的市场数量限制
    uint8 public constant JOINED_MKT_LIMIT = 20;

    ///@dev 标识符
    bool public constant IS_FLUX = true;

    /// @notice 禁止铸币(存币)
    bool public disableSupply;
    /// @notice 禁止借币
    bool public disableBorrow;
    /// @notice 锁住所有市场操作，在极端风险时允许通过锁住来抵抗极端风险
    bool public lockAllAction;

    /// @notice 禁止清算
    bool public liquidateDisabled;

    /**
     * @notice 已被登记的可借贷的市场基本信息，
     * 在批准特定资产可借贷时，将为其建立独立的借贷市场。
     */
    mapping(IMarket => Market) public markets;

    ///@notice 市场清单
    IMarket[] public marketList;

    /**
     * 所使用到的参数清单，每个值均已乘以 1e18。
     */
    mapping(string => uint256) public configs;

    // 用户已进入的市场清单
    mapping(address => EnumerableSet.AddressSet) internal acctJoinedMkts;
    /**
     @notice 当前已授权加入的资产借贷市场信息
     @dev key 为资产合约地址，value 为资产所对应的借贷市场
     */
    mapping(address => address) public supportTokens;

    mapping(address => uint256) public poolBorrowLimit;
}

contract AppStroageV2 is AppStroage {
    FluxMint public fluxMiner;
    IStake[] public stakePools;
    mapping(IStake => MarketStatus) public stakePoolStatus;

    mapping(address => LoanBorrowState) public LoanBorrowIndex;
}

struct LoanBorrowState {
    uint256 borrows;
    uint256 index;
}

contract AppStroageV3 is AppStroageV2 {
    // 清算线
    uint256 public constant KILL_FACTOR_MANTISSA = 1.1 * 1e18; //110%
    // 信用借款人清单
    mapping(address => bool) public creditBorrowers;
    // borrower => (market => limit)
    mapping(address => mapping(address => uint256)) public creditLimit;

    // 信用贷账户配置
    event CreditLoanChange(address indexed borrower, bool added);
    event CreditLoanLimitChange(address indexed borrower, address indexed market, uint256 limit, uint256 oldLimit);
}
