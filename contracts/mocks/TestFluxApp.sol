// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;
import "./Test.sol";
import "../FluxApp.sol";

contract FakeMarket {
    uint256 public exchangeRate;
    uint256 public decimals;

    constructor(uint256 decimals_) public {
        decimals = decimals_;
    }

    function setXRate(uint256 xrate_) public {
        exchangeRate = xrate_;
    }
}

contract TestFluxApp is FluxApp, Test {
    function before() public {
        // initialize(address(this));
        // oracle = new RandomPriceOracle();
        // fakeGateway.set("priceOracle", address(oracle));
    }

    // function testCalcCollTokens() public {
    //     // 创建两个市场
    //     FakeMarket m1 = new FakeMarket(16);
    //     FakeMarket m2 = new FakeMarket(12);
    //     //加入清单
    //     addMarket(address(m1), 1.12 * 1e18);
    //     addMarket(address(m2), 1.60 * 1e18);
    //     //m1.price m2.price m1.crate m2.xrate
    //     // 可兑换的m2 的 ftoken 数量为=  m1价格 * m1借款量 * m1抵押率 / m2价格/m2汇率
    //     uint256[6][4] memory caces = [
    //         // m1借款量 ，m1价格，  m1抵押率 ， m2价格，m2汇率，期望的m2.ftokens数量

    //         // 当借贷资产时同一种，且汇率为1 时，应该是还多少得多少
    //         [
    //             uint256(10 * 1e16),
    //             1000 * 1e18,
    //             1.2 * 1e18,
    //             1000 * 1e18,
    //             1.2 * 1e18,
    //             10 * 1e12
    //         ],
    //         // 抵押品价格为0.000001美元，计算时不会丢失精度
    //         [
    //             uint256(10 * 1e16),
    //             1000 * 1e18,
    //             1.2 * 1e18,
    //             0.000001 * 1e18,
    //             1.2 * 1e18,
    //             10000000000 * 1e12
    //         ],
    //         // 借款价格极小 0.0000001
    //         [
    //             uint256(1e14 * 1e16),
    //             0.00001 * 1e18,
    //             1.2 * 1e18,
    //             1.4 * 1e18,
    //             1.2 * 1e18,
    //             714285714.285714285714 * 1e12
    //         ],
    //         // 借款数量少，得到的 ftoken 也极少场景
    //         [
    //             uint256(1e-10 * 1e16),
    //             0.00001 * 1e18,
    //             1.2 * 1e18,
    //             0.00002 * 1e18,
    //             1.5 * 1e18,
    //             4e-11 * 1e12
    //         ]
    //     ];
    //     for (uint256 i = 0; i < caces.length; i++) {
    //         uint256[6] memory values = caces[i];
    //         oracle.setUnderlyingPrice(address(m1), values[1]);
    //         markets[IMarket(address(m1))].collRatioMan = values[2];
    //         oracle.setUnderlyingPrice(address(m2), values[3]);

    //         expectEqual(
    //             values[3],
    //             oracle.getUnderlyingPriceMan(address(m2)),
    //             "test"
    //         );

    //         m2.setXRate(values[4]);

    //         (uint256 err, uint256 got) = calcCollTokens(
    //             IMarket(address(m1)),
    //             IMarket(address(m2)),
    //             values[0]
    //         );

    //         expectEqual(OK, err, "期望计算不会失败");
    //         expectEqual(values[5], got, "可以赎回的ftokens计算正确");
    //     }
    // }

    // function addMarket(address m, uint256 v) public {
    //     IMarket addr = IMarket(m);
    //      markets[addr] = Market(true, v);
    //     marketList.push(addr);
    // }
}
