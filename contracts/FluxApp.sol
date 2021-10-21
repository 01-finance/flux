// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "./FluxStorage.sol";
import "./market/Interface.sol";
import "./lib/Ownable.sol";
import "./lib/Exponential.sol";
import "./lib/SafeMath.sol";
import "./lib/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

/**
  @title Flux-去中心借贷平台
  @dev Flux协议实现的核心，所有业务围绕 FluxApp 实现。
*/
contract FluxApp is Ownable, Initializable, AppStroageV3 {
    using Exponential for Exp;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 private constant DECIMAL_UNIT = 1e18;
    string private constant CONFIG_TEAM_INCOME_ADDRESS = "FLUX_TEAM_INCOME_ADDRESS";
    string private constant CONFIG_TAX_RATE = "MKT_BORROW_INTEREST_TAX_RATE";
    string private constant CONFIG_LIQUIDITY_RATE = "MKT_LIQUIDATION_FEE_RATE";
    /**
        @notice 市场状态被改变
        @param market 被改变的借贷市场
        @param oldStatus 改变前的市场状态
        @param newStatus 改变后的市场状态
     */
    event MarketStatusChagned(IMarket market, MarketStatus oldStatus, MarketStatus newStatus);

    /**
        @notice 参数变更事件
        @dev 表示 APP 所存储的可扩展参数 `mapping<string=>uint256> configs` 内容发生变化。
        @param item 变更项
        @param oldValue 变更前的值
        @param newValue 变更后的值
    */
    event ConfigChanged(string item, uint256 oldValue, uint256 newValue);
    /**
      @notice 新的借贷市场被批准
      @dev 当一个新的市场在 Flux 被授权加入，FluxApp 合约将产生 MarketApproved 事件。
      @param market 被授权加入的新借贷市场合约地址；
      @param collRatioMan 该借贷市场借款抵押率（尾数）。
     */
    event MarketApproved(IMarket market, uint256 collRatioMan);
    /**
      @notice 借贷市场被移除事件
      @param market 被移除的借贷市场合约地址
     */
    event MarketRemoved(IMarket market);

    /**
       @notice 借贷市场的抵押率修改事件
       @param market 被修改的借贷市场
       @param oldValue 修改前的抵押率（尾数）
       @param newValue 修改后的抵押率（尾数）
     */
    event MarketCollRationChanged(IMarket market, uint256 oldValue, uint256 newValue);
    event FluxMintChanged(FluxMint oldValue, FluxMint newValue);
    event StakePoolApproved(IStake pool, uint256 weights);
    event StakePoolStatusChanged(IStake indexed pool, MarketStatus oldValue, MarketStatus newValue);
    event StakePoolBorrowLimitChanged(IStake indexed pool, uint256 oldValue, uint256 newValue);
    event StakePoolRemoved(IStake indexed pool);

    /**
        @notice 初始化合约
        @dev 部署合约后需要在第一时间调用初始化合约，以便将信息在业务实施前设置。
        @param admin 管理员
     */
    function initialize(address admin) external initializer {
        initOwner(admin);

        address incomeAddr = 0xd34008Af58BA1DC1e1E8d8804f2BF745A18f38Bd;
        configs[CONFIG_TEAM_INCOME_ADDRESS] = uint256(incomeAddr);
        configs[CONFIG_TAX_RATE] = 0.1 * 1e18; //10%
        configs[CONFIG_LIQUIDITY_RATE] = 0.06 * 1e18; //6%
    }

    /**
       @notice 管理员修改配置项
       @dev 当前保留的存储信息，以便后续向 Flux 追加若干个配置项。
       @param item 配置项
       @param newValue 新值
     */
    function setConfig(string calldata item, uint256 newValue) external onlyOwner {
        uint256 old = configs[item];
        require(old != newValue, "NOTHING_MODIFIED");
        configs[item] = newValue;
        emit ConfigChanged(item, old, newValue);
    }

    /**
     * @notice 管理员批准指定的借贷市场进入Flux
     * @dev 这仅仅是在平台中批准借贷市场进入，但默认禁止操作的。需要在风控`Risk`中开启市场交易。
     * @param market 需要批准的借贷市场合约地址。
     * @param collRatioMan 该借贷市场的抵押率(尾数)，必须大于 100%。
     */
    function approveMarket(IMarket market, uint256 collRatioMan) external onlyOwner {
        require(market.isFluxMarket(), "NO_FLUX_MARKET");
        // 不允许重复
        require(markets[market].status == MarketStatus.Unknown, "MARKET_REPEAT");
        // 抵押率必须大于 100%
        require(1 * 1e18 < collRatioMan, "INVLIAD_COLLATERAL_RATE");
        // 检查风控是否已经允许该市场进入

        //check repeat
        address underlying = address(market.underlying());
        require(supportTokens[underlying] == address(0), "UNDERLYING_REPEAT");

        markets[market] = Market(MarketStatus.Opened, collRatioMan);
        marketList.push(market);
        supportTokens[underlying] = address(market);

        emit MarketApproved(market, collRatioMan);
    }

    /**
     * @notice 重置借贷市场的抵押率
     * @param market 需要修改的借贷市场合约地址。
     * @param collRatioMan 该借贷市场的抵押率，必须大于 100%。
     */
    function resetCollRatio(IMarket market, uint256 collRatioMan) external onlyOwner {
        Market storage info = markets[market];
        //不允许重复
        require(info.status != MarketStatus.Unknown, "MARKET_NOT_OPENED");
        require(info.collRatioMan != collRatioMan, "NOTHING_MODIFIED");

        // 抵押率必须大于 100%
        require(1e18 < collRatioMan, "INVLIAD_COLLATERAL_RATE");
        uint256 old = info.collRatioMan;
        markets[market].collRatioMan = collRatioMan;
        emit MarketCollRationChanged(market, old, collRatioMan);
    }

    /**
     *  @notice 移除指定的借贷市场
     *  @dev 移除前请确保市场状态已经是 Killed，不得随意移除市场。
     *  @param market 待移除的借贷市场
     */
    function removeMarket(IMarket market) external onlyOwner {
        Market storage mkt = markets[market];
        require(mkt.status == MarketStatus.Stopped, "MARKET_NOT_STOPPED");

        IERC20 underlying = market.underlying();
        require(underlying.balanceOf(address(market)) == 0, "MARKET_NOT_EMPTYE");

        //在移除前必须确保市场已经 Kill
        mkt.status = MarketStatus.Unknown;
        mkt.collRatioMan = 0;
        delete markets[market];
        delete supportTokens[address(market.underlying())];

        emit MarketRemoved(market);

        fluxMiner.removePool(address(market));

        // remove market from marketList
        uint256 len = marketList.length;
        for (uint256 i = 0; i < len; i++) {
            if (marketList[i] == market) {
                //find
                if (i != len - 1) {
                    marketList[i] = marketList[len - 1];
                }
                marketList.pop();
                break;
            }
        }
    }

    /**
     * @notice 查询指定的借贷市场信息
     * @param market 待查询的借贷市场
     * @return ratio 该借贷市场抵押率
     * @return status 该借贷市场状态（MarketStatus：Unknown、Opened、Stopped、Killed）
     */
    function marketStatus(IMarket market) public view returns (uint256 ratio, MarketStatus status) {
        Market storage mkt = markets[market];
        return (mkt.collRatioMan, mkt.status);
    }

    struct ValuesVars {
        address user;
        uint256 supplyValueMan;
        uint256 borrowValueMan;
        uint256 borrowLimitMan;
    }

    /**
      @dev 计算指定账户的资产信息，在计算时可以添加借款或存款来动态计算最终的借贷和抵押数据
      ⚠️ 因为计算结果是放大18倍，如果是存在一个天文的借贷信息，则会导致因为数据越界而无法累加。
      @return supplyValueMan 存款额（尾数）
      @return borrowValueMan 借款额（尾数）
      @return borrowLimitMan 借款限额（尾数）
     */
    function _calcAcct(
        address acct,
        address targetMarket,
        uint256 addBorrows,
        uint256 subSupplies
    )
        internal
        view
        returns (
            uint256 supplyValueMan,
            uint256 borrowValueMan,
            uint256 borrowLimitMan
        )
    {
        require(acct != address(0), "ADDRESS_IS_EMPTY");
        uint256 len = marketList.length;
        ValuesVars memory varsSum;
        ValuesVars memory vars;
        vars.user = acct;
        uint256 b;
        uint256 s;
        // 这里不限制数量，而是在进入市场时限制
        for (uint256 i = 0; i < len; i++) {
            IMarket m = marketList[i];
            if (address(m) == targetMarket) {
                b = addBorrows;
                s = subSupplies;
            } else {
                (b, s) = (0, 0);
            }
            (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = m.accountValues(vars.user, markets[m].collRatioMan, b, s);
            varsSum.supplyValueMan = varsSum.supplyValueMan.add(vars.supplyValueMan);
            varsSum.borrowValueMan = varsSum.borrowValueMan.add(vars.borrowValueMan);
            varsSum.borrowLimitMan = varsSum.borrowLimitMan.add(vars.borrowLimitMan);
        }
        return (varsSum.supplyValueMan, varsSum.borrowValueMan, varsSum.borrowLimitMan);
    }

    /**
     * @notice 查询账户借贷信息
     * @dev 一次性查询指定账户的借贷信息
     * @param acct 待查询账户
     * @return supplyValueMan uint256 存款额（尾数）
     * @return borrowValueMan uint256 借款额（尾数）
     * @return borrowLimitMan uint256 所需要的抵押额（尾数）
     */
    function getAcctSnapshot(address acct)
        public
        view
        returns (
            uint256 supplyValueMan,
            uint256 borrowValueMan,
            uint256 borrowLimitMan
        )
    {
        return _calcAcct(acct, address(0), 0, 0);
    }

    /**
      @notice  计算借款发生后账户的借贷信息
      @param borrower 借款人
      @param borrowMkt 借款市场
      @param amount 借款数量
     */
    function calcBorrow(
        address borrower,
        address borrowMkt,
        uint256 amount
    )
        public
        view
        returns (
            uint256 supplyValueMan,
            uint256 borrowValueMan,
            uint256 borrowLimitMan
        )
    {
        return _calcAcct(borrower, borrowMkt, amount, 0);
    }

    /**
        @notice 返回是否允许清算人清算借款人资产
        @param borrower 借款人
     */
    function liquidateAllowed(address borrower) public view returns (bool yes) {
        require(!liquidateDisabled, "RISK_LIQUIDATE_DISABLED");
        require(!creditBorrowers[borrower], "BORROWER_IS_CERDITLOAN");

        ValuesVars memory vars;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = getAcctSnapshot(borrower);
        if (vars.borrowValueMan == 0) {
            return false;
        }
        //当实时抵押率跌至清算抵押率时可以被清算
        //  存款额/借款  < 清算抵押率
        return Exp(vars.supplyValueMan).div(Exp(vars.borrowValueMan)).mantissa < CLOSE_FACTOR_MANTISSA;
    }

    /**
        @notice 登记账户进入/离开的市场集合
        @dev 记录的目的是，在统计账户借贷资产时，无需遍历所有市场进行查找。仅需要遍历已登记的市场即可。
        同时，对于每个借贷市场会记录所有曾经进入过的账户清单（增量）。
        该记录将会自动在借贷活动中由风控事件来执行。该方法只能被借贷市场调研
        @param acct address,待登记的账户地址
        @dev 只能被已加入的市场调研
     */
    function setAcctMarket(address acct, bool join) external {
        IMarket market = IMarket(msg.sender); //call from Market
        require(markets[market].status == MarketStatus.Opened, "MARKET_NOT_OPENED");

        EnumerableSet.AddressSet storage set = acctJoinedMkts[acct];
        if (!join) {
            //实时清理数据
            set.remove(address(market));
            delete markets[market].accountMembership[acct];
        } else {
            //重复添加时返回FALSE，如果成功添加，则判断是否超出数量限制，如果是则返回错误
            if (set.add(address(market))) {
                require(set.length() <= JOINED_MKT_LIMIT, "JOIN_TOO_MATCH");
                //进入市场
                markets[market].accountMembership[acct] = true;
            }
        }
    }

    /**
    @notice 借贷市场数量
    @return uint256 返回当前平台中借贷市场的个数。
 */
    function mktCount() external view returns (uint256) {
        return marketList.length;
    }

    /**
     * @notice 查询借贷市场是否已开启
     */
    function mktExist(IMarket mkt) external view returns (bool) {
        return markets[mkt].status == MarketStatus.Opened;
    }

    function getJoinedMktInfoAt(address acct, uint256 index) external view returns (IMarket mkt, uint256 collRatioMan) {
        mkt = IMarket(acctJoinedMkts[acct].at(index));
        collRatioMan = markets[mkt].collRatioMan;
    }

    function getAcctJoinedMktCount(address acct) external view returns (uint256) {
        return acctJoinedMkts[acct].length();
    }

    /**
        @notice 修改铸币（存款）可操作状态
        @param disable 为 TRUE 则禁用 Supply，否则解禁 Supply。
    */
    function changeSupplyStatus(bool disable) external onlyOwner {
        require(disableSupply != disable, "NOTHING_MODIFIED");
        disableSupply = disable;
        emit ConfigChanged("DISABLE_SUPPLY", disable ? 1 : 0, disable ? 0 : 1);
    }

    /**
        @notice 修改借币可操作状态
        @param disable 为 TRUE 则禁用 Borrow，否则解禁 Borrow。
    */
    function changeBorrowStatus(bool disable) external onlyOwner {
        require(disableBorrow != disable, "NOTHING_MODIFIED");
        disableBorrow = disable;
        emit ConfigChanged("DISABLE_BORROW", disable ? 1 : 0, disable ? 0 : 1);
    }

    /**
        @notice 修改清算可操作状态
     */
    function changeLiquidateStatus(bool disable) external onlyOwner {
        require(liquidateDisabled != disable, "NOTHING_MODIFIED");
        liquidateDisabled = disable;
        emit ConfigChanged("DISABLE_LIQUIDATE", disable ? 1 : 0, disable ? 0 : 1);
    }

    /**
        @notice 修改借币可操作状态
        @param disable 为 TRUE 则禁用 Supply，否则解禁 Supply。
    */
    function changeAllActionStatus(bool disable) external onlyOwner {
        require(lockAllAction != disable, "NOTHING_MODIFIED");
        lockAllAction = disable;
        emit ConfigChanged("DISABLE_ALL_ACTION", disable ? 1 : 0, disable ? 0 : 1);
    }

    /**
        @notice 设置市场状态
        @dev 市场状态有四种(Unkown,Opend,Stopped,Killed)，其修改状态顺序有一定规则。
        @param market 待修改状态的市场地址
        @param status 市场新状态
    */
    function setMarketStatus(IMarket market, MarketStatus status) external onlyOwner {
        Market storage mkt = markets[market];
        MarketStatus old = mkt.status;
        require(status != MarketStatus.Unknown, "INVLIAD_MARKET_STATUS");
        require(old != status, "INVLIAD_MARKET_STATUS");
        require(status <= MarketStatus.Stopped, "INVLIAD_MARKET_STATUS");
        mkt.status = status;
        emit MarketStatusChagned(market, old, status);
    }

    /**
     * @notice 修改借款限额
     */
    function setBorrowLimit(address[] calldata pools, uint256[] calldata limit) external onlyOwner {
        require(pools.length == limit.length, "INVLIAD_PARAMS");
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            uint256 oldValue = poolBorrowLimit[pool];
            uint256 newValue = limit[i];
            poolBorrowLimit[pool] = newValue;
            emit StakePoolBorrowLimitChanged(IStake(pool), oldValue, newValue);
        }
    }

    /**
     @notice 检查用户是否能够取款
     @dev 当用户取款时将需要检查用户所有用的资产能否足够取款，且在取款时借款抵押的资产不允许取走。
     将根据实时的资产价格计算用户资产，以检查用户的借款抵押率是否低于 `TOKEN_INSUFFICIENT_ALLOWANCE`
     @param acct 待检查的用户地址
     */
    function redeemAllowed(
        address acct,
        address mkt,
        uint256 ftokens
    ) public view {
        ValuesVars memory vars;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = _calcAcct(acct, mkt, 0, ftokens);
        if (vars.borrowValueMan == 0) {
            return;
        }
        // 借款限额被使用完则表示抵押不足，不得取款
        require(vars.borrowLimitMan >= vars.borrowValueMan, "REDEEM_INSUFFICIENT_COLLATERAL");
        //抵押率不得低于 115%
        require(Exp(vars.supplyValueMan).div(Exp(vars.borrowValueMan)).mantissa >= REDEEM_FACTOR_MANTISSA, "REDEEM_INSUFFICIENT_TOO_LOW");
    }

    function borrowAllowed(
        address borrower,
        address market,
        uint256 ctokens
    ) public view {
        require(ctokens > 0, "BORROW_IS_ZERO");
        require(!disableBorrow, "RISK_BORROW_DISABLED");
        _workingCheck(market);

        //借款不能超过限额
        uint256 limit = poolBorrowLimit[market];
        require(limit == 0 || IMarket(market).totalBorrows().add(ctokens) <= limit, "POOL_BORROW_EXCEEDED");

        ValuesVars memory vars;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = _calcAcct(borrower, market, ctokens, 0);

        //信用贷用户可以直接借款
        uint256 creditBorrowLimit = creditLimit[borrower][market];
        if (creditBorrowLimit > 0) {
            // 无需超过限制
            require(vars.borrowValueMan <= creditBorrowLimit, "BORROW_LIMIT_OUT");
            require(creditBorrowers[borrower], "NOT_FOUND_CERDITLOAN");
        } else {
            require(vars.borrowValueMan <= vars.borrowLimitMan, "BORROW_LIMIT_OUT");
            //抵押率不得低于110%
            require(Exp(vars.supplyValueMan).div(Exp(vars.borrowValueMan)).mantissa >= CLOSE_FACTOR_MANTISSA, "REDEEM_INSUFFICIENT_TOO_LOW");
        }
    }

    /**
     * @notice 存款（放贷）前风控检查
     * param  minter 存款人
     * @param market 借贷市场地址
     * param  ctokens 存入的标的资产数量
     */
    function beforeSupply(
        address, //minter,
        address market,
        uint256 //ctokens
    ) external view {
        require(!disableSupply, "RISK_DISABLE_MINT");
        _workingCheck(market);
    }

    function beforeTransferLP(
        address market,
        address from,
        address to,
        uint256 amount
    ) external {
        if (from != address(0)) {
            _workingCheck(market);
            redeemAllowed(from, market, amount);
            _settleOnce(market, TradeType.Supply, from);
        }

        if (to != address(0)) {
            _settleOnce(market, TradeType.Supply, to);
        }
    }

    /**
        @dev 检查市场是否可借贷，只有市场处于Open状态才允许借贷
     */
    function _workingCheck(address market) private view {
        require(!lockAllAction, "RISK_DISABLE_ALL");
        // 只有 open 状态的市场才允许交易
        require(markets[IMarket(market)].status == MarketStatus.Opened, "MARKET_NOT_OPENED");
    }

    /**
     @notice 借款前风控检查
     @param borrower 借款人
     @param market 借贷市场地址
     @param ctokens 待借入标的资产数量
     */
    function beforeBorrow(
        address borrower,
        address market,
        uint256 ctokens
    ) external {
        borrowAllowed(borrower, market, ctokens);
        _settleOnce(market, TradeType.Borrow, borrower);
    }

    /**
     @notice 取款（兑换）标的资产前风控检查
     @param redeemer 借款人
     @param market 借贷市场地址
     @param ftokens 待兑换的 ftoken 数量
     @dev 不管平台是否出现严重的安全问题，都允许用户取款
     */
    function beforeRedeem(
        address redeemer,
        address market,
        uint256 ftokens
    ) external view {
        _workingCheck(market);
        redeemAllowed(redeemer, market, ftokens);
    }

    function beforeRepay(
        address borrower,
        address market,
        uint256 //amount
    ) external {
        _workingCheck(market);
        _settleOnce(market, TradeType.Borrow, borrower);
    }

    function beforeLiquidate(
        address, //liquidator,
        address borrower,
        uint256 //amount
    ) external {
        address market = msg.sender;
        _workingCheck(market);
        _settleOnce(market, TradeType.Supply, borrower);
        _settleOnce(market, TradeType.Borrow, borrower);
    }

    /**
     * @notice 查询指定账户在给定市场的借款上线
     * @param acct 借款人地址
     * @param mkt 借款市场
     * @return limit 账户在该市场可借贷的资产数量
     * @return cash 该市场总现金数量
     * @dev 借款上限不能高于抵押品并且需要确保不会超出市场总量
     */
    function getBorrowLimit(IMarket mkt, address acct) external view returns (uint256 limit, uint256 cash) {
        cash = mkt.underlying().balanceOf(address(mkt));
        ValuesVars memory vars;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = _calcAcct(acct, address(mkt), 0, 0);

        //信用贷用户借款额度等于额度外的量
        uint256 creditBorrowLimit = creditLimit[acct][address(mkt)];
        if (creditBorrowLimit > 0) {
            vars.borrowLimitMan = creditBorrowLimit;
        }

        // 当已借款高出借款上限时，无法继续借款
        if (vars.borrowLimitMan <= vars.borrowValueMan) {
            return (0, cash);
        }
        uint256 unusedMan = vars.borrowLimitMan - vars.borrowValueMan;
        uint256 priceMan = mkt.underlyingPrice();
        uint256 tokenUnit = 10**(uint256(mkt.decimals()));
        limit = tokenUnit.mul(unusedMan).div(priceMan);
    }

    /**

        * @notice 查询指定账号的取款上限
         * @param acct 借款人地址
     * @param mkt 借款市场
     * @return limit 账户在该市场可借贷的资产数量
     * @return cash 该市场总现金数量
        @dev 取款上限不能超时取款警戒线
     */
    function getWithdrawLimit(IMarket mkt, address acct) external view returns (uint256 limit, uint256 cash) {
        cash = mkt.underlying().balanceOf(address(mkt));

        ValuesVars memory vars;
        vars.user = acct;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = _calcAcct(vars.user, address(mkt), 0, 0);
        //无存款，则为0
        if (vars.supplyValueMan == 0) {
            return (0, cash);
        }
        uint256 balance = mkt.balanceOf(acct);
        uint256 xrate = mkt.exchangeRate();
        uint256 supply = Exp(xrate).mulScalarTruncate(balance);
        // 无借款
        if (vars.borrowValueMan == 0) {
            //可以取走全部存款
            return (supply, cash);
        }
        // 不能超额度
        if (vars.borrowLimitMan <= vars.borrowValueMan) {
            return (0, cash);
        }
        // 不低于抵押率
        if (Exp(vars.supplyValueMan).div(Exp(vars.borrowValueMan)).mantissa <= REDEEM_FACTOR_MANTISSA) {
            return (0, cash);
        }

        ValuesVars memory mktVars;
        uint256 collRatio = markets[mkt].collRatioMan;
        (mktVars.supplyValueMan, mktVars.borrowValueMan, mktVars.borrowLimitMan) = mkt.accountValues(vars.user, collRatio, 0, 0);

        uint256 otherBorrowLimit = vars.borrowLimitMan.sub(mktVars.borrowLimitMan);

        //( mktSupply - withdraw)/ collRation + otherBorrowLimit >= borrows
        // withdraw= mktSupply - (borrows-otherBorrowLimit)*collRation

        // 如果其他资产的抵押品足够抵押借款，则该市场可以全部取走
        if (otherBorrowLimit >= vars.borrowValueMan) {
            return (supply, cash);
        }
        uint256 priceMan = mkt.underlyingPrice();
        uint256 used = vars.borrowValueMan - otherBorrowLimit;
        uint256 tokenUnit = 10**(uint256(mkt.decimals()));
        uint256 coll = tokenUnit.mul(used).mul(collRatio).div(priceMan).div(DECIMAL_UNIT);
        if (coll > supply) {
            limit = 0;
        } else {
            limit = supply - coll;
        }
    }

    /**################################################
    #      Flux Reward                                #
    ###################################################*/

    function setFluxMint(FluxMint fluxMiner_) external onlyOwner {
        FluxMint old = fluxMiner;
        require(address(old) == address(0), "REPEAT_INIT");
        emit FluxMintChanged(old, fluxMiner_);
        fluxMiner = fluxMiner_;
    }

    /**
     * @notice 刷新Flux分配比例
     */
    function refreshMarkeFluxSeed() external {
        require(msg.sender == tx.origin, "#FutureCore: SENDER_NOT_HUMAN");

        //执行复利
        uint256 len = marketList.length;
        for (uint256 i = 0; i < len; i++) {
            marketList[i].calcCompoundInterest();
        }
    }

    function _settleOnce(
        address pool,
        TradeType kind,
        address user
    ) private {
        FluxMint miner = fluxMiner;
        if (address(miner) != address(0)) {
            miner.settleOnce(pool, kind, user);
        }
    }

    /**################################################
    #      Stack Pool Manager                          #
    ###################################################*/

    /**
       @notice 新增抵押池
       @dev 当前保留的存储信息，以便后续向 Flux 追加若干个配置项。
       @param pool 抵押池
     */
    function stakePoolApprove(IStake pool, uint256 seed) external onlyOwner {
        require(stakePoolStatus[pool] == MarketStatus.Unknown, "STAKEPOOL_EXIST");
        stakePools.push(pool);
        stakePoolStatus[pool] = MarketStatus.Opened;

        fluxMiner.setPoolSeed(address(pool), seed);
        emit StakePoolApproved(pool, seed);
        emit StakePoolStatusChanged(pool, MarketStatus.Unknown, MarketStatus.Opened);
    }

    function setStakePoolStatus(IStake pool, bool opened) external onlyOwner {
        require(stakePoolStatus[pool] != MarketStatus.Unknown, "STAKEPOOL_MISSING");
        MarketStatus oldValue = stakePoolStatus[pool];
        MarketStatus newValue = opened ? MarketStatus.Opened : MarketStatus.Stopped;
        stakePoolStatus[pool] = newValue;
        emit StakePoolStatusChanged(pool, oldValue, newValue);
    }

    function beforeStake(address user) external {
        require(stakePoolStatus[IStake(msg.sender)] == MarketStatus.Opened, "STAKEPOOL_NOT_OPEN");
        _settleOnce(msg.sender, TradeType.Stake, user);
    }

    function beforeUnStake(address user) external {
        require(stakePoolStatus[IStake(msg.sender)] != MarketStatus.Unknown, "STAKEPOOL_NOT_FOUND");
        _settleOnce(msg.sender, TradeType.Stake, user);
    }

    function removeStakePool(IStake pool) external onlyOwner {
        require(stakePoolStatus[pool] == MarketStatus.Stopped, "STAKEPOOL_IS_NOT_STOPPED");
        // require(pool.totalStakeAt(type(uint256).max) == 0, "ASSET_IS_NOT_ZERO");
        uint256 len = stakePools.length;
        for (uint256 i = 0; i < len; i++) {
            if (stakePools[i] == pool) {
                stakePools[i] = stakePools[len - 1];
                stakePools.pop();
                emit StakePoolRemoved(pool);
                break;
            }
        }
    }

    /**
      @notice 获取市场地址清单
     */
    function getMarketList() external view returns (address[] memory list) {
        uint256 len = marketList.length;
        list = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            list[i] = address(marketList[i]);
        }
    }

    function getStakePoolList() external view returns (address[] memory list) {
        uint256 len = stakePools.length;
        list = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            list[i] = address(stakePools[i]);
        }
    }

    function getFluxTeamIncomeAddress() external view returns (address) {
        return address(configs[CONFIG_TEAM_INCOME_ADDRESS]);
    }

    //------------------
    // Flux V3
    //-------------------

    /**
      @notice 重置信用贷用户
      @dev 添加或者移除信用贷地址，添加进入信用贷的用户将被授权信用借款
     */
    function resetCreditLoan(address borrower, bool add) external onlyOwner {
        if (add) {
            creditBorrowers[borrower] = true;
        } else {
            require(creditBorrowers[borrower], "NOT_FOUND_CERDITLOAN");
            // 检查借款额
            (, uint256 borrowValueMan, ) = getAcctSnapshot(borrower);
            require(borrowValueMan == 0, "EXIST_CERDITLOAN");

            //移除时限额重置为0
            uint256 len = marketList.length;
            for (uint256 i = 0; i < len; i++) {
                resetCreditLoanLimit(address(marketList[i]), borrower, 0);
            }

            creditBorrowers[borrower] = false;
        }
        emit CreditLoanChange(borrower, add);
    }

    /**
      @notice 重置信用贷用户借款限额
      @dev 添加或者移除信用贷地址，添加进入信用贷的用户将被授权信用借款
     */
    function resetCreditLoanLimit(
        address market,
        address borrower,
        uint256 limit
    ) public onlyOwner {
        require(creditBorrowers[borrower], "NOT_FOUND_CERDITLOAN");
        uint256 oldLimit = creditLimit[borrower][market];
        creditLimit[borrower][market] = limit;
        emit CreditLoanLimitChange(borrower, market, limit, oldLimit);
    }

    /**
        @notice 返回是否允许清算人清算借款人资产
        @param borrower 借款人
     */
    function killAllowed(address borrower) external view returns (bool yes) {
        require(!liquidateDisabled, "RISK_LIQUIDATE_DISABLED");
        require(!creditBorrowers[borrower], "BORROWER_IS_CERDITLOAN");

        ValuesVars memory vars;
        (vars.supplyValueMan, vars.borrowValueMan, vars.borrowLimitMan) = getAcctSnapshot(borrower);
        if (vars.borrowValueMan == 0) {
            return false;
        }

        //当实时抵押率跌至清算抵押率时可以被清算
        //  存款额/借款  < 清算抵押率
        return Exp(vars.supplyValueMan).div(Exp(vars.borrowValueMan)).mantissa < KILL_FACTOR_MANTISSA;
    }
}
