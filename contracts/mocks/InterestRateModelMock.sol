// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../lib/SafeMath.sol";
import { IRModel } from "../market/Interface.sol";

// InterestRateModelMock
contract InterestRateModelMock is IRModel {
    uint256 urate = 0.1 * 1e18; //10%
    uint256 brate = 0.1 * 1e18; //10%
    uint256 srate = 0.1 * 1e18; //10%

    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view override returns (uint256) {
        cash;
        borrows;
        reserves;
        return urate;
    }

    function borrowRatePerSecond(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view override returns (uint256) {
        cash;
        borrows;
        reserves;
        return brate;
    }

    function supplyRatePerSecond(
        uint256 cash,
        uint256 supplies,
        uint256 borrows,
        uint256 reserves,
        uint256
    ) public view override returns (uint256) {
        supplies;
        cash;
        borrows;
        reserves;
        return srate;
    }

    function reset(
        uint256 urate_,
        uint256 brate_,
        uint256 srate_
    ) public {
        urate = urate_;
        srate = srate_;
        brate = brate_;
    }

    function execute(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public override {}
}
