// SPDX-License-Identifier: MIT
// Created by Flux Team
pragma solidity 0.6.8;

pragma experimental ABIEncoderV2;

import "../FluxApp.sol";
import "../FluxMint.sol";
import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";
import { ILPHelper } from "./NoramlSwapTokenPairHelper.sol";
import { IPriceOracle } from "../market/Interface.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

interface IStakePool is IERC20 {
    function lpToken() external view returns (address);
}

contract FluxReport is Ownable, Initializable {
    uint256 private constant DECIMAL_UNIT = 1e18;

    using SafeMath for uint256;
    FluxApp public core;
    FluxMint public fluxMiner;
    IPriceOracle public oracle;
    address public fluxToken;
    address public usdToken;
    ILPHelper public defaultLPHelper;

    mapping(address => ILPHelper) public stakeLPHelpers;
    mapping(address => address[]) public tokenSwapToUSDPath;

    function initialize(
        address admin,
        FluxApp _core,
        FluxMint _fluxMiner,
        IPriceOracle _oracle,
        address _fluxToken,
        address _usdToken,
        ILPHelper _defaultLPHeler
    ) public initializer {
        require(admin != address(0), "ADMIN_IS_EMPTY");
        require(address(_defaultLPHeler) != address(0), "helper is empty");
        initOwner(admin);

        core = _core;
        fluxMiner = _fluxMiner;
        oracle = _oracle;
        fluxToken = _fluxToken;
        usdToken = _usdToken;
        defaultLPHelper = _defaultLPHeler;

        address[] memory path = new address[](2);
        path[0] = _usdToken;
        path[1] = _fluxToken;
        tokenSwapToUSDPath[fluxToken] = path;
    }

    function setFLUX(address flux) external onlyOwner {
        fluxToken = flux;
    }

    function setLPHelper(ILPHelper helper) external onlyOwner {
        defaultLPHelper = helper;
    }

    function setHelper(address stakePool, ILPHelper helper) external onlyOwner {
        stakeLPHelpers[stakePool] = helper;
    }

    function setUSDToken(address token) external onlyOwner {
        require(address(token) != address(0), "token is empty");
        usdToken = token;
    }

    function setOracle(IPriceOracle _oracle) external onlyOwner {
        require(address(_oracle) != address(0), "oracle is empty");
        oracle = _oracle;
    }

    /**
     * 设置Token兑换路由，以便计算出 token 兑换价格。
     * 比如获取 FLUX 价格： path[usdt,flux]，则可以通过path计算需要多少 usdt 可以兑换到 1 flux。
     */
    function setTokenSwapToUSDPath(address[] calldata path) external onlyOwner {
        // remove
        if (path.length == 1) {
            delete tokenSwapToUSDPath[path[0]];
            return;
        }
        require(path.length >= 2, "invalid swap path");
        require(path[0] == usdToken, "the last token at path must be equal usdToken");
        tokenSwapToUSDPath[path[path.length - 1]] = path;
    }

    /**
     * 获取Flux协议总TVL
     */
    function getFluxTVL() external view returns (uint256 tvl) {
        {
            LoanPoolReport[] memory pools = getLoanPoolReport();
            for (uint256 i = 0; i < pools.length; i++) {
                tvl = tvl.add(pools[i].tvl);
            }
        }

        {
            StakePoolReport[] memory pools = getStakePoolReport();
            for (uint256 i = 0; i < pools.length; i++) {
                tvl = tvl.add(pools[i].tvl);
            }
        }
    }

    /**
     * 获取 Flux TVL 各项数据，包括总借款，总存款和总抵押
     */
    function getFluxTVLDetail()
        external
        view
        returns (
            uint256 totalSupply,
            uint256 totalBorrow,
            uint256 totalStaked
        )
    {
        {
            LoanPoolReport[] memory pools = getLoanPoolReport();
            for (uint256 i = 0; i < pools.length; i++) {
                IMarket mkt = IMarket(pools[i].pool);
                uint256 units = 10**(uint256(mkt.decimals()));
                totalSupply = totalSupply.add(pools[i].totalSupply.mul(pools[i].priceUSD).div(units));
                totalBorrow = totalBorrow.add(pools[i].totalBorrow.mul(pools[i].priceUSD).div(units));
            }
        }

        {
            StakePoolReport[] memory pools = getStakePoolReport();
            for (uint256 i = 0; i < pools.length; i++) {
                totalStaked = totalStaked.add(pools[i].tvl);
            }
        }
    }

    struct LoanPoolReport {
        address pool; //借贷池合约地址
        uint256 tvl; // TVL=总存款
        uint256 totalSupply; //总存款数量
        uint256 totalBorrow; //总借款数量
        uint256 priceUSD; //资产价格
        uint256 supplyInterestPreDay; //存款日利率
        uint256 borrowInterestPreDay; //借款日利率
        uint256 supplyFluxAPY; // 存款 FLUX年化收益率
        uint256 borrowFluxAPY; // 借款 FLUX年化收益率
        address underlying; //底层资产地址
    }

    function getLoanPoolReport() public view returns (LoanPoolReport[] memory pools) {
        address[] memory markets = core.getMarketList();
        pools = new LoanPoolReport[](markets.length);
        uint256 fluxPrice = getFluxPrice();

        for (uint256 i = 0; i < markets.length; i++) {
            IMarket mkt = IMarket(markets[i]);

            uint256 cash = mkt.cashPrior();
            uint256 borrows = mkt.totalBorrows();
            uint256 price = mkt.underlyingPrice();
            uint256 units = 10**(uint256(mkt.decimals()));

            uint256 supplyValue = cash.add(borrows).mul(price).div(units);
            uint256 borrowValue = borrows.mul(price).div(units);
            pools[i].pool = address(mkt);
            pools[i].totalSupply = cash.add(borrows);
            pools[i].totalBorrow = borrows;
            pools[i].priceUSD = price;
            pools[i].underlying = address(mkt.underlying());
            pools[i].tvl = supplyValue;

            (pools[i].borrowInterestPreDay, pools[i].supplyInterestPreDay, ) = mkt.getAPY();
            pools[i].supplyInterestPreDay = (pools[i].supplyInterestPreDay / (365 days)) * (24 hours);
            pools[i].borrowInterestPreDay = (pools[i].borrowInterestPreDay / (365 days)) * (24 hours);

            // FLUX APY

            (uint256 bySupply, uint256 byBorrow) = getFluxMintedNextBlock(address(mkt));
            if (supplyValue > 0) {
                uint256 oneYear = bySupply.mul(365 days);
                pools[i].supplyFluxAPY = oneYear.mul(fluxPrice).div(supplyValue);
            }
            if (borrowValue > 0) {
                uint256 oneYear = byBorrow.mul(365 days);
                pools[i].borrowFluxAPY = oneYear.mul(fluxPrice).div(borrowValue);
            }
        }
    }

    struct StakePoolReport {
        address pool; //抵押池合约地址
        uint256 tvl; //抵押池TVL
        uint256 apy; //抵押池FLUX产出年化收益率
        address token0; //抵押池对应资产token0
        address token1; //抵押池对应资产token1
        uint256 token0Staked; //抵押池对应资产token0质押数量
        uint256 token1Staked; //抵押池对应资产token1质押数量
        uint256 token0PriceUSD; // token0 价格
        uint256 token1PriceUSD; // token1 价格
    }

    function getStakePoolReport() public view returns (StakePoolReport[] memory pools) {
        address[] memory stakePools = core.getStakePoolList();
        pools = new StakePoolReport[](stakePools.length);
        uint256 fluxPrice = getFluxPrice();

        for (uint256 i = 0; i < stakePools.length; i++) {
            IStakePool pool = IStakePool(stakePools[i]);
            StakePoolReport memory report;
            report.pool = address(pool);

            ILPHelper helper = stakeLPHelpers[report.pool];

            if (address(helper) == address(0)) {
                helper = defaultLPHelper;
            }
            // lp -> token0+token1
            (report.token0, report.token0Staked, report.token1, report.token1Staked) = helper.getTokenAmount(pool.lpToken(), report.pool);

            // value = amount/units * price
            uint256 uints = 10**(uint256(INormalERC20(report.token0).decimals()));

            report.token0PriceUSD = getTokenPrice(report.token0);
            report.tvl = report.token0PriceUSD.mul(report.token0Staked).div(uints);

            if (report.token1 != address(0)) {
                uints = 10**(uint256(INormalERC20(report.token1).decimals()));
                report.token1PriceUSD = getTokenPrice(report.token1);
                report.tvl = report.tvl.add(report.token1PriceUSD.mul(report.token1Staked).div(uints));
            }
            if (report.tvl > 0) {
                //计算 FLUX 奖励
                (uint256 minted, ) = getFluxMintedNextBlock(report.pool);
                uint256 oneYear = minted.mul(365 days);
                report.apy = oneYear.mul(fluxPrice).div(report.tvl);
            }

            pools[i] = report;
        }
    }

    function getTokenPrice(address token) public view returns (uint256) {
        if (token == usdToken) {
            return 1e18;
        }
        if (token == address(0)) {
            return 0;
        }
        //如果有设置，则优先使用
        {
            address[] memory path = tokenSwapToUSDPath[token];
            if (path.length > 0) {
                return defaultLPHelper.getTokenPrice(path);
            }
        }
        return oracle.getPriceMan(token);
    }

    function getFluxPrice() public view returns (uint256) {
        return getTokenPrice(fluxToken);
    }

    /// @dev 实现 Oracle 接口
    function getPriceMan(address token) external view returns (uint256) {
        return getTokenPrice(token);
    }

    function getFluxMintedNextBlock(address mkt) public view returns (uint256 bySupply, uint256 byBorrow) {
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
}
