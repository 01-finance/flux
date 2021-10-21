// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../market/MarketCFX.sol";
import "../market/MarketERC20.sol";

contract MarketCFXMock is MarketCFX {
    mapping(string => bool) private enables;
    uint256 private _rate = 1e18;

    function enableFunc(string memory key, bool ye) public {
        enables[key] = ye;
    }

    function calcCompoundInterest() public override {
        if (enables["calcCompoundInterest"]) {
            super.calcCompoundInterest();
        }
    }

    function setExchangeRate(uint256 rate) public {
        _rate = rate;
    }

    function exchangeRate() public view virtual override returns (uint256) {
        if (enables["exchangeRate"]) {
            return super.exchangeRate();
        }
        if (_rate == 0) {
            return 1e18;
        }
        return _rate;
    }
}

contract MarketERC20Mock is MarketERC20 {
    mapping(string => bool) private enables;
    uint256 private _rate = 1e18;

    function enableFunc(string memory key, bool ye) public {
        enables[key] = ye;
    }

    function calcCompoundInterest() public override {
        if (enables["calcCompoundInterest"]) {
            super.calcCompoundInterest();
        }
    }

    function setExchangeRate(uint256 rate) public {
        _rate = rate;
    }

    function exchangeRate() public view virtual override returns (uint256) {
        if (enables["exchangeRate"]) {
            return super.exchangeRate();
        }
        if (_rate == 0) {
            return 1e18;
        }
        return _rate;
    }
}
