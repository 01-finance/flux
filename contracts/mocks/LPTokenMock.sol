// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "./ERC20Mock.sol";
import "./WHTMock.sol";

contract LPTokenMock is TokenMock {
    TokenMock public underlyingToken;
    TokenMock public underlyingToken2;

    constructor(
        TokenMock _underlying,
        TokenMock _underlying2,
        string memory _name,
        string memory _symbol
    ) public TokenMock(_name, _symbol, 18) {
        underlyingToken = _underlying;
        underlyingToken2 = _underlying2;
    }

    function redeem(uint256 amount) external returns (uint256 err) {
        _burn(msg.sender, amount);
        underlyingToken.mint(msg.sender, amount);
        if (address(underlyingToken2) != address(0)) {
            underlyingToken2.mint(msg.sender, amount * 2);
        }
        return 0;
    }
}

contract LPCoinTokenMock is ERC20 {
    WHTMock public underlyingToken;

    constructor(
        WHTMock _underlying,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol) {
        underlyingToken = _underlying;
    }

    function mint() external payable {
        underlyingToken.deposit{ value: msg.value }();
        _mint(msg.sender, msg.value);
    }

    function redeem(uint256 amount) external returns (uint256 err) {
        _burn(msg.sender, amount);
        underlyingToken.withdraw(amount);

        msg.sender.transfer(amount);

        return 0;
    }

    receive() external payable {}
}
