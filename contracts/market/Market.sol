// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "./Interface.sol";
import "../lib/SafeMath.sol";
import "../lib/Exponential.sol";
import "../lib/PubContract.sol";
import "../lib/Ownable.sol";
import "./FToken.sol";

import { MarketStatus } from "../FluxApp.sol";
import { IFluxCross } from "../cross/Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INormalERC20 } from "./Interface.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

/**
   @title 借贷市场
   @dev 在 Flux 中被借贷的资产（标的物）是符合 ERC20 标准的 Token， 资产即可以是 Conflux 上的原始代币，也可是通过侧链系统链接的以太坊 ERC20 代币，我们统称资产为 *cToken*。
    任一资产需要在批准后才能被允许交易，且 Flux 专门为 *cToken* 开设**独立的**借贷市场 $a$，但该场所也符合 ERC20 标准，因此命名为 *fToken*。  fToken 价值由兑换汇率决定。
 */
abstract contract Market is Initializable, Ownable, FToken, ReentrancyGuard, MarketStorage {
    using SafeMath for uint256;
    using Exponential for Exp;
    using SafeERC20 for IERC20;

    string private constant CONFIG_TAX_RATE = "MKT_BORROW_INTEREST_TAX_RATE";
    uint256 private constant MAX_LIQUIDATE_FEERATE = 0.1 * 1e18; //10%

    /**
     * @notice 存款事件
       @param supplyer 取款人（兑换人）
       @param ctokens 最终兑换的标的资产数量
       @param ftokens 用于兑换标的资产的 ftoken 数量
     */
    event Supply(address indexed supplyer, uint256 ctokens, uint256 ftokens, uint256 balance);

    /**
     * @notice 取款事件
       @param redeemer 取款人（兑换人）
       @param receiver 接收代币的账户（如果不为空则为以太坊账户地址）
       @param ftokens 用于兑换标的资产的 ftoken 数量
       @param ctokens 最终兑换的标的资产数量
     */
    event Redeem(address indexed redeemer, string receiver, uint256 ftokens, uint256 ctokens);

    /**
        @notice 借款事件
        @param borrower 借款人
        @param receiver 接收代币的账户（如果不为空则为以太坊账户地址）
        @param ctokens 借款人所借走的标的资产数量
        @param borrows 借款人当前的借款余额，含应付利息
        @param totalBorrows 市场总借款额，含应付利息
     */
    event Borrow(address indexed borrower, string receiver, uint256 ctokens, uint256 borrows, uint256 totalBorrows);

    /**
        @notice 还款事件
        @param repayer 还款人
        @param repaid 还款人实际还款的标的资产数量
        @param borrows 还款人剩余的借款余额，含应付利息
        @param totalBorrows 市场总借款额，含应付利息
     */
    event Repay(address indexed repayer, uint256 repaid, uint256 borrows, uint256 totalBorrows);

    /**
        @notice 借款人抵押品被清算事件
        @param liquidator 清算人
        @param borrower 借款人
        @param supplies  存款
        @param borrows  借款
     */
    event Liquidated(address indexed liquidator, address indexed borrower, uint256 supplies, uint256 borrows);
    event ChangeOracle(IPriceOracle oldValue, IPriceOracle newValue);

    /**
     * @notice 初始化
     * @dev  在借贷市场初始化时设置货币基础信息。
     * @param guard_ Flux核心合约
     * @param oracle_ 预言机
     * @param interestRateModel_ 利率模型
     * @param underlying_ FToken 的标的资产地址
     * @param name_ FToken名称
     * @param symbol_ FToken 货币标识符
     */
    function initialize(
        address guard_,
        address oracle_,
        address interestRateModel_,
        address underlying_,
        string calldata name_,
        string calldata symbol_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _decimals = INormalERC20(underlying_).decimals(); //精度等同于标的资产精度
        interestIndex = 1e18; //设置为最小值
        initialExchangeRateMan = 1e18;
        lastAccrueInterest = block.timestamp;

        underlying = IERC20(underlying_);
        guard = Guard(guard_);
        app = FluxApp(guard.flux());
        oracle = IPriceOracle(oracle_);
        interestRateModel = IRModel(interestRateModel_);
        //set admin
        initOwner(guard.owner());

        //safe check
        uint256 price = underlyingPrice();
        bool ye = app.IS_FLUX();
        uint256 rate = getBorrowRate();
        require(price > 0, "UNDERLYING_PRICE_IS_ZERO");
        require(ye, "REQUIRE_FLUX");
        require(rate > 0, "BORROW_RATE_IS_ZERO");
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        app.beforeTransferLP(address(this), from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (from != address(0)) {
            _updateJoinStatus(from);
        }
        if (to != address(0)) {
            _updateJoinStatus(to);
        }
    }

    /**
      @dev 允许为每个市场设置不同的价格预言机，以便从不同的数据源中获取价格。比如 MoonDex，Chainlink.
     */
    function changeOracle(IPriceOracle oracle_) external onlyOwner {
        emit ChangeOracle(oracle, oracle_);
        oracle = oracle_;
        //check
        underlyingPrice();
    }

    /**
     * @notice 获取该市场所拥有的标的资产余额（现金）
     * @dev 仅仅是 fToken.balaceOf(借贷市场)
     * @return 借贷市场合约所拥有的标的资产数量
     */
    function cashPrior() public view virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function underlyingTransferIn(address sender, uint256 amount) internal virtual returns (uint256 actualAmount);

    function underlyingTransferOut(address receipt, uint256 amount) internal virtual returns (uint256 actualAmount);

    function getBorrowRate() internal view returns (uint256 rateMan) {
        return interestRateModel.borrowRatePerSecond(cashPrior(), totalBorrows, taxBalance);
    }

    // -------------------------借贷业务 -------------------------
    /**
      @dev 复利计算
     */
    function calcCompoundInterest() public virtual {
        // 区块间隔 times = 当前区块时间 block.timestarp - 最后一次计息时间 lastAccrueInterest
        // 区间借款利率 rate =  区间间隔 times * 单区块借款利率 blockBorrowRate
        // 总借款 totalBorrows = 总借款 totalBorrows + 借款利息
        //                    =  totalBorrows + totalBorrows * 利率 rate
        uint256 currentNumber = block.timestamp;
        uint256 times = currentNumber.sub(lastAccrueInterest);
        // 一个区块仅允许更新一次
        if (times == 0) {
            return;
        }
        uint256 oldBorrows = totalBorrows;
        uint256 reserves = taxBalance;

        //执行利率模型的 execute
        interestRateModel.execute(cashPrior(), oldBorrows, reserves);

        Exp memory rate = Exp(getBorrowRate()).mulScalar(times);
        uint256 oldIndex = interestIndex;
        uint256 interest = rate.mulScalarTruncate(oldBorrows);
        //收取借款利息税
        uint256 taxRate = getTaxRate();

        taxBalance = reserves.add(interest.mul(taxRate).div(1e18));

        totalBorrows = oldBorrows.add(rate.mulScalarTruncate(oldBorrows));
        interestIndex = oldIndex.add(rate.mulScalarTruncate(oldIndex));
        lastAccrueInterest = currentNumber;
    }

    function getTaxRate() public view returns (uint256 taxRate) {
        string memory key = string(abi.encodePacked("TAX_RATE_", _symbol));
        taxRate = app.configs(key);
        if (taxRate == 0) {
            taxRate = app.configs(CONFIG_TAX_RATE);
        }
    }

    function _supply(address minter, uint256 ctokens) internal nonReentrant {
        require(borrowBalanceOf(minter) == 0, "YOU_HAVE_BORROW");

        require(ctokens > 0, "SUPPLY_IS_ZERO");
        calcCompoundInterest();
        // / 风控检查
        app.beforeSupply(minter, address(this), ctokens);

        require(underlyingTransferIn(msg.sender, ctokens) == ctokens, "TRANSFER_INVLIAD_AMOUNT");

        _mintStorage(minter, ctokens);
    }

    function _mintStorage(address minter, uint256 ctokens) private {
        Exp memory exchangeRate = Exp(_exchangeRate(ctokens));
        require(!exchangeRate.isZero(), "EXCHANGERATE_IS_ZERO");
        uint256 ftokens = Exponential.divScalarByExpTruncate(ctokens, exchangeRate);
        ftokens = ftokens == 0 && ctokens > 0 ? 1 : ftokens;
        _mint(minter, ftokens);
        emit Supply(minter, ctokens, ftokens, balanceOf(minter));
    }

    /**
     @notice 取款（兑换标的资产）
     @dev 放贷人将其账户下 将 `amount` 量的资产提现 ，并转给指定的接受者 *recevier* ，
        但需要确保待兑换的 fToken 充足，不可透支，账户总借款抵押率不能低于 110% 。
     @param amount 待用于兑换标的资产的 ftoken 数量
     @param isWithdraw 表示是否是提现，提现将有更多检查
     @return actual 成功时返回成功兑换的标的资产数量。
     */
    function _redeem(
        address redeemer,
        address to,
        uint256 amount,
        bool isWithdraw
    ) internal nonReentrant returns (uint256 actual) {
        calcCompoundInterest();

        uint256 ftokens;
        uint256 ctokenAmount;

        Exp memory exchangeRate = Exp(exchangeRate());
        require(!exchangeRate.isZero(), "EXCHANGERATE_IS_ZERO");

        //当为外部提现时，amount 表示要提现的资产数量，需要计算对于的 ftoken 数量
        //但当 amount==0 时需要根据 ftoken 计算
        if (isWithdraw && amount > 0) {
            ctokenAmount = amount;
            ftokens = Exponential.divScalarByExpTruncate(ctokenAmount, exchangeRate);
            ftokens = ftokens == 0 && ctokenAmount > 0 ? 1 : ftokens; //弥补精度缺失
        } else {
            // amount 为 0 表示提现全部
            ftokens = amount == 0 ? balanceOf(redeemer) : amount;
            ctokenAmount = exchangeRate.mulScalarTruncate(ftokens);
            ctokenAmount = ftokens > 0 && ctokenAmount == 0 ? 1 : ctokenAmount; //弥补精度缺失
        }

        //检查该市场是否有足够的现金供使用
        // 更新
        _burn(redeemer, ftokens, isWithdraw);
        require(underlyingTransferOut(to, ctokenAmount) == ctokenAmount, "INVALID_TRANSFER_OUT");

        //风控检查
        //取款则销毁ftoken, ftoken 已被兑换成 ctoken
        emit Redeem(redeemer, "", ftokens, ctokenAmount);
        return ctokenAmount;
    }

    /**
        @dev 借入标的资产，借款必须有足够的资产进行抵押
     */
    function _borrow(address to, uint256 ctokens) internal nonReentrant {
        address borrower = msg.sender;
        require(balanceOf(borrower) == 0, "YOUR_HAVE_SUPPLY");

        calcCompoundInterest();
        // 为了避免出现资产价值用整数表达时归零的问题，而做出的借款限制
        require(ctokens >= 10**(uint256((_decimals * 2) / 5 + 1)), "BORROWS_TOO_SMALL");
        //检查市场是否有足够的现金供借出
        // require(cashPrior() >= ctokens, "Marekt: Insufficient cash available"); //skip:  transfer token will be check
        // 风控检查
        app.beforeBorrow(borrower, address(this), ctokens);
        /**
            更新当前借款
            borrows=  borrowBalanceOf(borrower) + ctokens;
            totalBorrows += ctokens;
        */
        totalBorrows = totalBorrows.add(ctokens);
        uint256 borrowsNew = borrowBalanceOf(borrower).add(ctokens);
        _borrowStorage(borrower, borrowsNew);
        //转账
        require(underlyingTransferOut(to, ctokens) == ctokens, "INVALID_TRANSFER_OUT");
        emit Borrow(borrower, "", ctokens, borrowsNew, totalBorrows);
    }

    function _repay(address repayer, uint256 ctokens) internal {
        // guard by _repayFor
        _repayFor(repayer, repayer, ctokens);
    }

    /**
      @notice 还款
      @dev 借款人偿还本息，多余还款将作为存款存入市场。
      @param repayer 还款人
      @param borrower 借款人
      @param ctokens 还款的标的资产数量
     */
    function _repayFor(
        address repayer,
        address borrower,
        uint256 ctokens
    ) internal nonReentrant {
        calcCompoundInterest();
        // 风控检查
        app.beforeRepay(repayer, address(this), ctokens);
        require(_repayBorrows(repayer, borrower, ctokens) > 0, "REPAY_IS_ZERO");
    }

    /// @dev 任何人均可帮助借款人还款，还款剩余部分转入还款人名下
    function _repayBorrows(
        address repayer,
        address borrower,
        uint256 repays
    ) private returns (uint256 actualRepays) {
        uint256 borrowsOld = borrowBalanceOf(borrower);
        if (borrowsOld == 0) {
            return 0;
        }

        if (repays == 0) {
            repays = actualRepays = borrowsOld;
        } else {
            actualRepays = SafeMath.min(repays, borrowsOld);
        }
        // 转移资产
        require(underlyingTransferIn(repayer, actualRepays) == actualRepays, "TRANSFER_INVLIAD_AMOUNT");
        //更新
        totalBorrows = totalBorrows.sub(actualRepays);
        uint256 borrowsNew = borrowsOld - actualRepays;
        _borrowStorage(borrower, borrowsNew);
        emit Repay(borrower, actualRepays, borrowsNew, totalBorrows);
    }

    ///@dev 更新借款信息
    function _borrowStorage(address borrower, uint256 borrowsNew) private {
        if (borrowsNew == 0) {
            delete userFounds[borrower];
            return;
        }
        CheckPoint storage user = userFounds[borrower];
        user.interestIndex = interestIndex;
        user.borrows = borrowsNew;
        _updateJoinStatus(borrower);
    }

    function liquidatePrepare(address borrower)
        external
        returns (
            IERC20 asset,
            uint256 ftokens,
            uint256 borrows
        )
    {
        calcCompoundInterest();
        asset = underlying;
        ftokens = balanceOf(borrower);
        borrows = borrowBalanceOf(borrower);
    }

    /**
     * @notice 清算账户资产
     * @param liquidator 清算人
     * @param borrower 借款人
     * @param feeCollector 清算收费员
     * @param feeRate 清算费率
     */
    function liquidate(
        address liquidator,
        address borrower,
        address feeCollector,
        uint256 feeRate
    ) external returns (bool ok) {
        address guardAddr = address(guard);
        require(msg.sender == guardAddr, "LIQUIDATE_INVALID_CALLER");

        require(liquidator != borrower, "LIQUIDATE_DISABLE_YOURSELF");

        calcCompoundInterest();

        uint256 ftokens = balanceOf(borrower);
        uint256 borrows = borrowBalanceOf(borrower);

        //偿还借款
        if (borrows > 0) {
            require(underlyingTransferIn(msg.sender, borrows) == borrows, "TRANSFER_INVLIAD_AMOUNT");
            totalBorrows = totalBorrows.sub(borrows);
            _borrowStorage(borrower, 0);
        }

        //获得抵押品
        uint256 supplies;
        if (ftokens > 0) {
            require(feeRate <= MAX_LIQUIDATE_FEERATE, "INVALID_FEERATE");
            Exp memory exchangeRate = Exp(exchangeRate());
            supplies = exchangeRate.mulScalarTruncate(ftokens);
            require(cashPrior() >= supplies, "MARKET_CASH_INSUFFICIENT");

            _burn(borrower, ftokens, false);
            uint256 fee = supplies.mul(feeRate).div(1e18);
            underlyingTransferOut(liquidator, supplies.sub(fee)); //剩余归清算人
            if (fee > 0) {
                if (feeCollector != address(0)) {
                    uint256 feeHalf = fee / 2;
                    underlyingTransferOut(feeCollector, fee - feeHalf); //一半手续费归Flux 团队
                    underlyingTransferOut(guardAddr, feeHalf); //一半手续费用于穿仓清算备用
                } else {
                    underlyingTransferOut(guardAddr, fee); //手续费用于穿仓清算
                }
            }
        }
        emit Liquidated(liquidator, borrower, supplies, borrows);
        return true;
    }

    /**
      @notice 穿仓清算
      @dev 当穿仓时Flux将在交易所中卖出用户所有资产，以便偿还借款。注意，只有 Flux 合约才有权限执行操作。
     */
    function killLoan(address borrower) external returns (uint256 supplies, uint256 borrows) {
        address guardAddr = address(guard);
        //只能由Guard执行
        require(msg.sender == guardAddr, "MARGINCALL_INVALID_CALLER");
        require(guardAddr != borrower, "DISABLE_KILL_GURAD");

        //计息
        calcCompoundInterest();

        //没收全部存款到Guard名下
        uint256 ftokens = balanceOf(borrower);

        app.beforeLiquidate(msg.sender, borrower, ftokens);

        if (ftokens > 0) {
            Exp memory exchangeRate = Exp(exchangeRate());
            supplies = exchangeRate.mulScalarTruncate(ftokens);
            //潜在风险，资金池借空无法提现
            uint256 cash = cashPrior();
            if (cash < supplies) {
                //将存款凭证转移给 Guard
                _transfer(borrower, guardAddr, ftokens, false);
            } else {
                _burn(borrower, ftokens, false);
                underlyingTransferOut(guardAddr, supplies); //迁移至清算合约
            }
        }
        // 将借款转移到Guard名下
        borrows = borrowBalanceOf(borrower);
        if (borrows > 0) {
            _borrowStorage(borrower, 0); // 转移到 Gurad 名下
            _borrowStorage(guardAddr, borrowBalanceOf(guardAddr).add(borrows));
        }
        if (borrows > 0 || supplies > 0) {
            emit Liquidated(guardAddr, borrower, supplies, borrows);
        }
    }

    ///@dev 实时更新账户在各借贷市场的进出情况，如果更新时机不正确，会影响账户借贷资产的统计
    function _updateJoinStatus(address acct) internal {
        app.setAcctMarket(acct, balanceOf(acct) > 0 || borrowBalanceOf(acct) > 0);
    }

    // ------------------------- 借贷业务  end-------------------------

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
        )
    {
        uint256 taxRate = getTaxRate();
        uint256 balance = cashPrior();

        borrowRate = interestRateModel.borrowRatePerSecond(balance, totalBorrows, taxBalance) * (365 days);
        supplyRate = interestRateModel.supplyRatePerSecond(balance, totalSupply(), totalBorrows, taxBalance, taxRate) * (365 days);
        utilizationRate = interestRateModel.utilizationRate(balance, totalBorrows, taxBalance);
    }

    // 各类系数计算
    /**
     * @notice 获取 fToken 与标的资产 cToken 的兑换汇率
     * @dev  fToken 的兑换率等于（总现金+ 总借款 - 总储备金） / 总fToken代币 == （ totalCash + totalBorrows - totalReservers ）/ totalSupply
     * @return (exchangeRateMan)
     */
    function exchangeRate() public view virtual returns (uint256) {
        return _exchangeRate(0);
    }

    /**
      @dev 允许调整cash数量，因为一些操作时实际上 cash 或 supply 已不精准，需要调整。
     */
    function _exchangeRate(uint256 ctokens) private view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            // 尚未供给时，兑换汇率为初始默认汇率
            return initialExchangeRateMan;
        }
        //汇率
        //= cToken量 / fToken量
        //=（总现金+ 总借款 - 总储备金 - 利息税） / 总fToken代币
        //= （ totalCash + totalBorrows - totalReservers  -taxBalance ）/ totalSupply
        uint256 totalCash = cashPrior();
        totalCash = totalCash.sub(ctokens);
        uint256 cTokenAmount = totalCash.add(totalBorrows).sub(taxBalance);
        uint256 rate = Exponential.get(cTokenAmount, totalSupply_).mantissa;
        if (rate == 0) {
            return initialExchangeRateMan;
        }
        return rate;
    }

    /**
      @notice 查询账户借款数量
      @param acct 需要查询的账户地址
      @return uint256 账户下的标的资产借款数量，包括应付利息
     */
    function borrowBalanceOf(address acct) public view returns (uint256) {
        /**
           借款本息
            = 当前本息 * 复利
            = borrower.borrows* ( interestIndex/borrower.interestIndex)
         */
        CheckPoint storage borrower = userFounds[acct];
        uint256 borrows = borrower.borrows;
        if (borrows == 0) {
            return 0;
        }
        uint256 index = borrower.interestIndex;
        if (index == 0) {
            return borrows;
        }
        Exp memory rate = Exponential.get(interestIndex, index);
        return rate.mulScalarTruncate(borrows);
    }

    /**
     @notice 获取账户借贷信息快照
     @param acct 待查询的账户地址
     @return ftokens 存款余额
     @return borrows 借款余额，含利息
     @return xrate 汇率
    */
    function getAcctSnapshot(address acct)
        external
        view
        returns (
            uint256 ftokens,
            uint256 borrows,
            uint256 xrate
        )
    {
        return (balanceOf(acct), borrowBalanceOf(acct), exchangeRate());
    }

    /**
        @dev 用于复杂计算时的数据存储
     */
    struct CalcVars {
        uint256 supplies;
        uint256 borrows;
        uint256 priceMan;
        Exp borrowLimit;
        Exp supplyValue;
        Exp borrowValue;
    }

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
        )
    {
        CalcVars memory vars;

        // 存款 = 当前存款 - subSupplies
        vars.supplies = balanceOf(acct).sub(subSupplies, "TOKEN_INSUFFICIENT_BALANCE");
        // 借款数 = 当前借款 + addBorrows
        vars.borrows = borrowBalanceOf(acct).add(addBorrows);
        if (vars.supplies == 0 && vars.borrows == 0) {
            return (0, 0, 0);
        }

        // 自此的价格是 一个币的价格，比如 1 FC ，
        // 但下面计算时 存款量/借款量 都是最小精度表达的。
        // 因此，计算时需要除以 10^decimals 。
        vars.priceMan = underlyingPrice();
        require(vars.priceMan > 0, "MARKET_ZERO_PRICE");

        if (vars.supplies > 0) {
            // 存款市值 = 汇率 * 存款量 * 价格
            // supplyValue  = exchangeRate * supplies * price
            // supplyValue * 1e18 = 1e18 * exchangeRate/1e18 * supplies/10^_decimals * price/1e18
            //                    = exchangeRate * supplies * price/(10^(18+_decimals)  )
            supplyValueMan = exchangeRate().mul(vars.supplies).mul(vars.priceMan).div(10**(18 + uint256(_decimals)));
            //借款限额 = 存款市值 / 抵
            borrowLimitMan = supplyValueMan.mul(1e18).div(collRatioMan);
        }
        if (vars.borrows > 0) {
            // 借款市值 = 借款量 * 价格
            // borrowValue =  borrows * price
            borrowValueMan = vars.priceMan.mul(vars.borrows).div(10**uint256(_decimals));
        }
    }

    function underlyingPrice() public view returns (uint256) {
        return oracle.getPriceMan(address(underlying));
    }

    function isFluxMarket() external pure returns (bool) {
        return true;
    }

    function borrowAmount(address acct) external view returns (uint256) {
        return userFounds[acct].borrows;
    }

    /**
       @notice 任意账户可以执行提取利差到团队收益账户
     */
    function withdrawTax() external {
        address receiver = app.getFluxTeamIncomeAddress();
        require(receiver != address(0), "RECEIVER_IS_EMPTY");
        uint256 tax = taxBalance; //save gas
        require(tax > 0, "TAX_IS_ZERO");
        taxBalance = 0;
        require(underlyingTransferOut(receiver, tax) == tax, "TAX_TRANSFER_FAILED");
    }

    function enableCross(address fluxCrossHandler) external onlyOwner {
        fluxCross = fluxCrossHandler; //ignore event
    }

    /**
     * @notice 跨链调仓
     * @dev 允许将资产从跨链提取到其他链中
     * @param tragetChainId 目标链ID
     * @param amount 跨链调仓 token 数量
     * @param maxFluxFee 跨链调仓支付的FLUX手续费最大数量
     */
    function crossRefinance(
        uint64 tragetChainId,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable {
        address cross = fluxCross;
        require(cross != address(0), "CROSS_NOT_READY");
        _redeem(msg.sender, cross, amount, true);
        IFluxCross(cross).deposit{ value: msg.value }(tragetChainId, msg.sender, address(underlying), amount, maxFluxFee);
    }

    function crossRedeem(
        uint64 tragetChainId,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable {
        address cross = fluxCross;
        require(cross != address(0), "CROSS_NOT_READY");
        _redeem(msg.sender, cross, amount, true);
        IFluxCross(cross).withdraw{ value: msg.value }(tragetChainId, msg.sender, address(underlying), amount, maxFluxFee);
    }

    function crossBorrow(
        uint64 tragetChainId,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable {
        address cross = fluxCross;
        require(cross != address(0), "CROSS_NOT_READY");
        _borrow(cross, amount);
        IFluxCross(cross).withdraw{ value: msg.value }(tragetChainId, msg.sender, address(underlying), amount, maxFluxFee);
    }
}
