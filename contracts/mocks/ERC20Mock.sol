// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() public ERC20("TEST", "TEST") {
        _setupDecimals(18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function beg(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}

contract CTokenMock is ERC20Mock {
    function burn(
        address user_addr, // user conflux address
        uint256 amount, // burn amount
        uint256 expected_fee, // expected burn fee, in 18 decimals
        string calldata addr, // external chain receive address
        address defi_relayer // external chain defi relayer address
    ) external {
        _burn(user_addr, amount);
    }
}

contract TokenMock is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public ERC20(_name, _symbol) {
        _setupDecimals(_decimals);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function beg(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
