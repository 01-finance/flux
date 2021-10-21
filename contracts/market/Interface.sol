// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import { IPriceOracle } from "./PriceOracle.sol";
import { Guard } from "./Guard.sol";
import { FluxApp } from "../FluxApp.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 @title Flux 利率模型接口
 @dev 利率模型借款是为 Flux 指导利率，是借款利息计算的重要依据。
 */
interface IRModel {
    /**
        @notice 求借款利率（区块）
        @param cash 市场尚未被借出的资产放贷数量
        @param borrows 市场已被借出的资产数量
        @param reserves 平台对该资产的储备量
     */
    function borrowRatePerSecond(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);

    /**
        @notice 求存款放贷利率（区块）
        @param cash 市场尚未被借出的资产放贷数量
        @param borrows 市场已被借出的资产数量
        @param reserves 平台对该资产的储备量
     */
    function supplyRatePerSecond(
        uint256 cash,
        uint256 supplies,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);

    /**
        @notice 求资金使用率
        @param cash 市场尚未被借出的资产放贷数量
        @param borrows 市场已被借出的资产数量
        @param reserves 平台对该资产的储备量
     */
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);

    function execute(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external;
}

/**
 * @title 借贷市场
 */
interface IMarket is IERC20 {
    function decimals() external view returns (uint8);

    function cashPrior() external view returns (uint256);

    function interestIndex() external view returns (uint256);

    function borrowAmount(address acct) external view returns (uint256);

    function underlying() external view returns (IERC20);

    function totalBorrows() external view returns (uint256);

    function underlyingPrice() external view returns (uint256);

    function isFluxMarket() external pure returns (bool);

    /**
      @notice 获取市场兑换汇率
      @return 返回汇率的尾数
     */
    function exchangeRate() external view returns (uint256);

    /**
     @notice 获取账户借贷信息快照
     @param acct 待查询的账户地址
     @return uint256 存款余额
     @return uint256 借款余额，含利息
     @return uint256 汇率
    */
    function getAcctSnapshot(address acct)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    /**
        @notice 计算账户借贷资产信息
        @dev 通过提供多个参数来灵活的计算账户的借贷时的资产变动信息，比如可以查询出账户如果继续借入 200 个 FC 后的借贷情况。
        @param acct 待查询账户
        @param collRatioMan 计算时使用的借款抵押率
        @param addBorrows 计算时需要增加的借款数量
        @param subSupplies 计算时需要减少的存款数量
      @return supplyValueMan 存款额（尾数）
      @return borrowValueMan 借款额（尾数）
      @return borrowLimitMan 借款所需抵押额（尾数）
     */
    function accountValues(
        address acct,
        uint256 collRatioMan,
        uint256 addBorrows,
        uint256 subSupplies
    )
        external
        view
        returns (
            uint256 supplyValueMan,
            uint256 borrowValueMan,
            uint256 borrowLimitMan
        );

    /**
        @notice 索取借款人的抵押品
        @dev 借款市场可以调用此抵押品市场来索取借款人的抵押品给清算人，该方法的调用者只能是Flux借贷市场。
        @param liquidator 清算人
        @param borrower 借款人
        @param collTokens 抵押品数量
     */
    function seize(
        address liquidator,
        address borrower,
        uint256 collTokens
    ) external;

    /**
        @notice 复利计息
     */
    function calcCompoundInterest() external;

    /**
       @notice 获取该市场的借贷利率
       @return borrowRate 借款年利率（尾数）
       @return supplyRate 存款年利率（尾数）
       @return utilizationRate 资金使用率（尾数）
     */
    function getAPY()
        external
        view
        returns (
            uint256 borrowRate,
            uint256 supplyRate,
            uint256 utilizationRate
        );
}

struct CheckPoint {
    uint256 borrows; //借款余额
    uint256 interestIndex; //借款/还款时的市场借款利息指数
}

contract MarketStorage {
    // FToken 内部存储
    IERC20 public underlying;
    IPriceOracle public oracle;
    IRModel public interestRateModel;
    FluxApp public app;
    Guard public guard;
    address payable public withdrawProxy; // 代理提现WHT/WETH...

    //------------借贷信息 ----------
    /// @notice 初始汇率尾数
    uint256 internal initialExchangeRateMan = 1e18;
    /// @notice 最后一次计息时间（区块高度）
    uint256 public lastAccrueInterest;
    /// @notice 当前已借出但尚未归还的资产数量。
    uint256 public totalBorrows;
    /// @notice 累积借款利率指数
    uint256 public interestIndex = 1e18;
    // 市场用户资金信息
    mapping(address => CheckPoint) internal userFounds;
    ///@notice 借款利息税
    uint256 public taxBalance;

    address public fluxCross; //Flux跨链
}

interface INormalERC20 is IERC20 {
    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() external view returns (uint8);
}
