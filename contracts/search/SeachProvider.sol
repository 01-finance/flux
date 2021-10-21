// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

pragma experimental ABIEncoderV2;

import "../FluxApp.sol";
import "../FluxMint.sol";
import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";

import { IPriceOracle } from "../market/Interface.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

/**
 * @notice 数据查询辅助库
 * @dev 不涉及FLUX借贷，无需审计
 */
contract SearchProvider is Ownable, Initializable {
    using SafeMath for uint256;
    FluxApp public core;
    FluxMint public fluxMiner;
    IPriceOracle public oracle;
    address public fluxToken;

    uint16 private constant WEIGHT_UNIT = 1e4;
    uint256 private constant DECIMAL_UNIT = 1e18;

    struct SummaryVars {
        int256 apy;
        uint256 loanIncome;
        uint256 loanExpenses;
        uint256 fluxIncome;
        uint256 supplyValue;
        uint256 borrowValue;
        address[] markets;
        int256[] supplyAPYs;
        int256[] borrowAPYs;
        int256[] borrowFluxAPYs;
        int256[] supplyFluxAPYs;
        uint256[] supply;
        uint256[] borrow;
    }
    struct LoanSum {
        uint256 supplyValue;
        uint256 borrowValue;
        uint256 supply;
        uint256 borrow;
        uint256 loanIncome;
        uint256 loanExpenses;
        uint256 fluxIncome;
        int256 supplyAPY;
        int256 borrowAPY;
        int256 supplyFluxAPY;
        int256 borrowFluxAPY;
    }

    struct SearchVars {
        IMarket mkt;
        uint256 supply;
        uint256 borrow;
        uint256 exchangeRate;
        uint256 price;
        uint256 seed;
        uint256 fluxPrice;
        uint256 supplyRate;
        uint256 borrowRate;
        uint256 fluxOneYear;
    }

    function initialize(
        address admin,
        FluxApp _core,
        FluxMint _fluxMiner,
        IPriceOracle _oracle,
        address _fluxToken
    ) public initializer {
        require(admin != address(0), "ADMIN_IS_EMPTY");
        initOwner(admin);

        core = _core;
        fluxMiner = _fluxMiner;
        oracle = _oracle;
        fluxToken = _fluxToken;
    }

    function release() external onlyOwner {
        selfdestruct(msg.sender);
    }

    function changeOracle(IPriceOracle oracle_) external onlyOwner {
        oracle = oracle_;
    }

    function setFluxToken(address token) external onlyOwner {
        fluxToken = token; //允许为空
    }

    /**
     *@notice 查询指定账户的投资年化收益率
     *@param user 待查询用户地址
     *@return SummaryVars 净收益率
     */
    function getProfitability(address user) external view returns (SummaryVars memory) {
        FluxApp flux = core;
        address _user = user;

        uint256 mktCount = flux.getAcctJoinedMktCount(_user);

        uint256 fluxOneYear = fluxMiner.calcFluxsMined(block.timestamp, block.timestamp + 1) * 365 days;
        uint256 fluxPrice = oracle.getPriceMan(fluxToken);

        SummaryVars memory sum;
        sum.borrowFluxAPYs = new int256[](mktCount);
        sum.supplyFluxAPYs = new int256[](mktCount);
        sum.borrowAPYs = new int256[](mktCount);
        sum.supplyAPYs = new int256[](mktCount);
        sum.supply = new uint256[](mktCount);
        sum.borrow = new uint256[](mktCount);
        sum.markets = new address[](mktCount);

        //遍历所有市场计算出所有市场收益率
        for (uint256 i = 0; i < mktCount; i++) {
            (IMarket mkt, ) = flux.getJoinedMktInfoAt(_user, i);

            LoanSum memory loanSum = _loanProfitability(address(mkt), _user, fluxPrice, fluxOneYear);

            sum.loanIncome += loanSum.loanIncome;
            sum.loanExpenses += loanSum.loanExpenses;
            sum.fluxIncome += loanSum.fluxIncome;
            sum.supplyValue += loanSum.supplyValue;
            sum.borrowValue += loanSum.borrowValue;

            sum.supply[i] = loanSum.supply;
            sum.borrow[i] = loanSum.borrow;
            sum.supplyAPYs[i] = loanSum.supplyAPY;
            sum.borrowAPYs[i] = loanSum.borrowAPY;
            sum.supplyFluxAPYs[i] = loanSum.supplyFluxAPY;
            sum.borrowFluxAPYs[i] = loanSum.borrowFluxAPY;
            sum.markets[i] = address(mkt);
        }

        // net apy = (存款利息-借款利息+FLUX奖励)/存款
        if (sum.supplyValue > 0) {
            if (sum.loanExpenses < sum.loanIncome + sum.fluxIncome) {
                sum.apy = int256(((sum.loanIncome + sum.fluxIncome - sum.loanExpenses) * DECIMAL_UNIT) / sum.supplyValue);
            } else {
                sum.apy = -int256(((sum.loanExpenses - sum.loanIncome - sum.fluxIncome) * DECIMAL_UNIT) / sum.supplyValue);
            }
        }
        return sum;
    }

    function loanProfitability(IMarket mkt, address user) external view returns (LoanSum memory sum) {
        uint256 fluxPrice = oracle.getPriceMan(fluxToken);
        uint256 fluxOneYear = fluxMiner.calcFluxsMined(block.timestamp, block.timestamp + 360 days);
        sum = _loanProfitability(address(mkt), user, fluxPrice, fluxOneYear);
    }

    function _loanProfitability(
        address mkt,
        address user,
        uint256 fluxPrice,
        uint256 fluxOneYear
    ) private view returns (LoanSum memory sum) {
        //借款奖励+存款奖励
        IMarket _mkt = IMarket(mkt);
        SearchVars memory vars;
        vars.mkt = _mkt;
        vars.fluxOneYear = fluxOneYear;
        (vars.supply, vars.borrow, vars.exchangeRate) = _mkt.getAcctSnapshot(user);
        (vars.borrowRate, vars.supplyRate, ) = _mkt.getAPY();
        vars.price = _mkt.underlyingPrice();
        vars.fluxPrice = fluxPrice;
        vars.seed = fluxMiner.fluxSeeds(address(_mkt));

        uint256 fluxIncome1;
        uint256 fluxIncome2;
        (sum.supplyValue, sum.loanIncome, fluxIncome1, sum.supplyAPY) = _supplyProfitability(vars);
        (sum.borrowValue, sum.loanExpenses, fluxIncome2, sum.borrowAPY) = _borrowProfitability(vars);
        if (sum.supplyValue > 0) sum.supplyFluxAPY = int256((fluxIncome1 * DECIMAL_UNIT) / sum.supplyValue);
        if (sum.borrowValue > 0) sum.borrowFluxAPY = int256((fluxIncome2 * DECIMAL_UNIT) / sum.borrowValue);
        sum.fluxIncome = fluxIncome1 + fluxIncome2;
        sum.supply = (vars.supply * vars.exchangeRate) / DECIMAL_UNIT;
        sum.borrow = vars.borrow;
    }

    function _borrowProfitability(SearchVars memory vars)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            int256
        )
    {
        if (vars.borrow == 0) {
            return (0, 0, 0, 0);
        }
        //借款利息
        uint256 tokenUnit = 10**uint256(vars.mkt.decimals());
        uint256 borrowValue = (vars.borrow * vars.price) / tokenUnit;
        uint256 loanExpenses = (vars.borrowRate * borrowValue) / DECIMAL_UNIT;
        uint256 totalBorrow = vars.mkt.totalBorrows();

        //FLUX奖励
        (, uint256 amount) = getLoanFluxMinted(address(vars.mkt));
        // 奖励的FLUX代币数量= FLUX未来一年开采量*存款分配比例*该市场分配比例*该用户分配比
        uint256 currFlux = totalBorrow == 0 ? 0 : amount.mul(365 days).mul(vars.borrow).div(totalBorrow);
        uint256 currFluxValue = currFlux.mul(vars.fluxPrice).div(DECIMAL_UNIT);

        // 当前借款成本 = （代币奖励 - 借款利息）/借款
        int256 _borrowAPY;
        if (borrowValue > 0) {
            if (currFluxValue > loanExpenses) {
                _borrowAPY = int256(((currFluxValue - loanExpenses) * DECIMAL_UNIT) / borrowValue);
            } else {
                _borrowAPY = -int256(((loanExpenses - currFluxValue) * DECIMAL_UNIT) / borrowValue);
            }
        }
        return (borrowValue, loanExpenses, currFluxValue, _borrowAPY);
    }

    struct FLUXAPYVars {
        uint256 bySupply;
        uint256 byBorrow;
        uint256 fluxPrice;
    }

    function getLonFluxAPY(IMarket mkt) external view returns (uint256 supplyFluxAPY, uint256 borrowFluxAPY) {
        FLUXAPYVars memory vars;
        (vars.bySupply, vars.byBorrow) = getLoanFluxMinted(address(mkt));
        vars.fluxPrice = oracle.getPriceMan(fluxToken);

        //计算当前存款的年利息
        uint256 totalSupply = mkt.totalSupply();
        uint256 totalBorrow = mkt.totalBorrows();
        uint256 price = mkt.underlyingPrice();

        uint256 tokenUnit = 10**uint256(mkt.decimals());
        uint256 exchangeRate = mkt.exchangeRate();
        uint256 supplyValue = exchangeRate.mul(totalSupply).div(DECIMAL_UNIT).mul(price).div(tokenUnit);
        uint256 borrowValue = totalBorrow.mul(price).div(tokenUnit);

        //  FLUX年收益/总借款
        uint256 fluxTokenUnit = 1e18;
        if (supplyValue > 0) {
            uint256 oneYear = vars.bySupply.mul(365 days);
            uint256 fluxValue = oneYear.mul(vars.fluxPrice).div(fluxTokenUnit);
            supplyFluxAPY = fluxValue.mul(DECIMAL_UNIT).div(supplyValue);
        }
        if (borrowValue > 0) {
            uint256 oneYear = vars.byBorrow.mul(365 days);
            uint256 fluxValue = oneYear.mul(vars.fluxPrice).div(fluxTokenUnit);
            borrowFluxAPY = fluxValue.mul(DECIMAL_UNIT).div(borrowValue);
        }
    }

    function getLoanFluxMinted(address mkt) public view returns (uint256 bySupply, uint256 byBorrow) {
        uint256 fromBlock = block.timestamp;
        uint256 endBlock = fromBlock + 1;

        uint256 baseMined = fluxMiner.fluxsMinedBase(fromBlock, endBlock);
        uint256 genusisMined = fluxMiner.fluxsMinedGenusis(fromBlock, endBlock);

        //每个借贷池的产出分配比例
        (uint256 borrowWeight, uint256 supplyWeight) = fluxMiner.getPoolSeed(mkt);
        (uint256 gb, uint256 gs) = fluxMiner.getGenesisWeight(mkt);

        //该借贷池所分配的头矿产出
        {
            uint256 byBase = baseMined.mul(supplyWeight) / DECIMAL_UNIT;
            bySupply = byBase.add(genusisMined.mul(gs) / DECIMAL_UNIT);
        }
        {
            uint256 byBase = baseMined.mul(borrowWeight) / DECIMAL_UNIT;
            byBorrow = byBase.add(genusisMined.mul(gb) / DECIMAL_UNIT);
        }
    }

    function _supplyProfitability(SearchVars memory vars)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            int256
        )
    {
        if (vars.supply == 0) {
            return (0, 0, 0, 0);
        }
        uint256 tokenUnit = 10**uint256(vars.mkt.decimals());

        uint256 totalSupply = vars.mkt.totalSupply();

        //存款额
        uint256 supplyValue = (((vars.exchangeRate * vars.supply) / tokenUnit) * vars.price) / DECIMAL_UNIT;

        // 存款利息
        uint256 loanIncome = (vars.supplyRate * supplyValue) / DECIMAL_UNIT;

        //FLUX奖励
        (uint256 amount, ) = getLoanFluxMinted(address(vars.mkt));
        // 奖励的FLUX代币数量= FLUX未来一年开采量*存款分配比例*该市场分配比例*该用户分配比
        uint256 currFlux = totalSupply == 0 ? 0 : amount.mul(365 days).mul(vars.supply).div(totalSupply);
        uint256 currFluxValue = currFlux.mul(vars.fluxPrice).div(DECIMAL_UNIT);

        //该市场的存款年化= (存款利息+代币奖励)/存款
        int256 _supplyAPY = supplyValue > 0 ? int256(((loanIncome + currFluxValue) * DECIMAL_UNIT) / supplyValue) : 0;

        return (supplyValue, loanIncome, currFluxValue, _supplyAPY);
    }

    /**
      @notice 获取指定账户尚未领取的FLUX余额
     */
    function unclaimedFlux(address user) public view returns (uint256) {
        FluxMint miner = fluxMiner;
        (uint256 rewards1, , , ) = unclaimedFluxAtLoan(user);
        (uint256 rewards2, , ) = unclaimedFluxAtStake(user);
        return rewards1 + rewards2 + miner.remainFluxByUser(user);
    }

    /**
      @notice 获取借贷市场中尚未领取的Flux
      @return total 所有借贷市场累积未领取
      @return markets 借贷市场清单
      @return bySupply 每个借贷市场中对应的因存款而获得的未领取的FLUX代币
      @return byBorrow 每个借贷市场中对应的因借款而获得的未领取的FLUX代币
     */
    function unclaimedFluxAtLoan(address user)
        public
        view
        returns (
            uint256 total,
            address[] memory markets,
            uint256[] memory bySupply,
            uint256[] memory byBorrow
        )
    {
        markets = core.getMarketList();

        bySupply = new uint256[](markets.length);
        byBorrow = new uint256[](markets.length);

        FluxMint miner = fluxMiner;

        for (uint256 i = 0; i < markets.length; i++) {
            address mkt = markets[i];
            bySupply[i] = miner.getFluxRewards(mkt, TradeType.Supply, user);
            byBorrow[i] = miner.getFluxRewards(mkt, TradeType.Borrow, user);

            total += bySupply[i];
            total += byBorrow[i];
        }
    }

    /**
      @notice 获取抵押市场中尚未领取的Flux
      @return total 所有抵押市场累积未领取
      @return stakePools 抵押市场清单
      @return rewards 每个抵押市场中对应的因抵押而获得的未领取的FLUX代币
     */
    function unclaimedFluxAtStake(address user)
        public
        view
        returns (
            uint256 total,
            address[] memory stakePools,
            uint256[] memory rewards
        )
    {
        stakePools = core.getStakePoolList();
        rewards = new uint256[](stakePools.length);
        FluxMint miner = fluxMiner;

        for (uint256 i = 0; i < stakePools.length; i++) {
            rewards[i] = miner.getFluxRewards(stakePools[i], TradeType.Stake, user);
            total += rewards[i];
        }
    }

    function stakeSummary(address staker)
        external
        view
        returns (
            address[] memory stakePools,
            uint256[] memory totalStakes,
            uint256[] memory stakes,
            uint256[] memory _unlaimedFlux
        )
    {
        stakePools = core.getStakePoolList();
        uint256 len = stakePools.length;
        totalStakes = new uint256[](len);
        stakes = new uint256[](len);
        _unlaimedFlux = new uint256[](len);

        FluxMint miner = fluxMiner;
        for (uint256 i = 0; i < len; i++) {
            IStake s = IStake(stakePools[i]);
            stakes[i] = s.stakeAmountAt(staker, type(uint256).max);
            totalStakes[i] = s.totalStakeAt(type(uint256).max);
            _unlaimedFlux[i] = miner.getFluxRewards(stakePools[i], TradeType.Stake, staker);
        }
    }
}
