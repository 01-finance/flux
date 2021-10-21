// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

interface ISwapFactory {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/**
 * 获取来自Swap中的FLUX价格USD
 */
contract FluxSwapOracleAggregatorBSCMDEX {
    uint256 public constant decimals = 8;
    string public constant dtoryescription = "FluxSwapOracleAggregator";
    uint256 public constant version = 1;

    address public constant SWAP_ROUNTER = address(0x3CD1C46068dAEa5Ebb0d3f55F6915B10648062B8);
    address private constant FLUX = address(0x0747CDA49C82d3fc6B06dF1822E1DE0c16673e9F);
    address private constant USDT = address(0x55d398326f99059fF775485246999027B3197955);

    address private admin;

    constructor() public {
        admin = msg.sender;
        //check
        require(IERC20Decimals(FLUX).decimals() > 0, "missing FLUX ERC20");
        require(IERC20Decimals(USDT).decimals() > 0, "missing USDT ERC20");
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        require(_roundId == 1, "only for round 1");
        answer = int256(getUSDPrice());
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80 roundId
        )
    {
        roundId = 1;
        answer = int256(getUSDPrice());
    }

    function getUSDPrice() public view returns (uint256) {
        uint256 fluxDecimals = uint256(IERC20Decimals(FLUX).decimals());
        uint256 usdDecimals = uint256(IERC20Decimals(USDT).decimals());

        uint256 outOneFLUX = 10**fluxDecimals;
        address[] memory path = new address[](2);
        // from  usdt -> flux(1e18)
        path[0] = USDT;
        path[1] = FLUX;

        ISwapFactory factory = ISwapFactory(SWAP_ROUNTER);
        uint256[] memory amounts = factory.getAmountsIn(outOneFLUX, path);
        //amounts[0]= usdt amount , amounts[1]= flux amount 1e18
        return (amounts[0] * 1e8) / (10**usdDecimals);
    }

    function finalize() external {
        require(msg.sender == admin, "caller is not admin");
        selfdestruct(msg.sender);
    }
}

contract FluxSwapOracleAggregatorOEC {
    uint256 public constant decimals = 8;
    string public constant dtoryescription = "FluxSwapOracleAggregator";
    uint256 public constant version = 1;

    address public constant SWAP_ROUNTER = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); //SUSHI Router
    address private constant FLUX = address(0xd0C6821aba4FCC65e8f1542589e64BAe9dE11228); //FLUXK
    address private constant USDT = address(0x382bB369d343125BfB2117af9c149795C6C65C50);

    address private admin;

    constructor() public {
        admin = msg.sender;
        //check
        require(IERC20Decimals(FLUX).decimals() > 0, "missing FLUX ERC20");
        require(IERC20Decimals(USDT).decimals() > 0, "missing USDT ERC20");
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        require(_roundId == 1, "only for round 1");
        answer = int256(getUSDPrice());
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80 roundId
        )
    {
        roundId = 1;
        answer = int256(getUSDPrice());
    }

    function getUSDPrice() public view returns (uint256) {
        uint256 usdDecimals = 18;
        uint256 outOneFLUX = 1e18;
        address[] memory path = new address[](2);
        // from  usdt -> flux(1e18)
        path[0] = USDT;
        path[1] = FLUX;
        ISwapFactory factory = ISwapFactory(SWAP_ROUNTER);
        uint256[] memory amounts = factory.getAmountsIn(outOneFLUX, path);
        //amounts[0]= usdt amount , amounts[1]= flux amount 1e18
        return (amounts[0] * 1e8) / (10**usdDecimals);
    }

    function finalize() external {
        require(msg.sender == admin, "caller is not admin");
        selfdestruct(msg.sender);
    }
}

contract FluxSwapOracleAggregatorPolygon {
    uint256 public constant decimals = 8;
    string public constant dtoryescription = "FluxSwapOracleAggregator";
    uint256 public constant version = 1;

    address public constant SWAP_ROUNTER = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff); //QuickSwap: Router
    address private constant FLUX = address(0xd10852DF03Ea8b8Af0CC0B09cAc3f7dbB15e0433);
    address private constant USDT = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

    address private admin;

    constructor() public {
        admin = msg.sender;
        //check
        require(IERC20Decimals(FLUX).decimals() > 0, "missing FLUX ERC20");
        require(IERC20Decimals(USDT).decimals() > 0, "missing USDT ERC20");
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        require(_roundId == 1, "only for round 1");
        answer = int256(getUSDPrice());
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80 roundId
        )
    {
        roundId = 1;
        answer = int256(getUSDPrice());
    }

    function getUSDPrice() public view returns (uint256) {
        uint256 usdDecimals = 6;
        uint256 outOneFLUX = 1e18;
        address[] memory path = new address[](2);
        // from  usdt -> flux(1e18)
        path[0] = USDT;
        path[1] = FLUX;
        ISwapFactory factory = ISwapFactory(SWAP_ROUNTER);
        uint256[] memory amounts = factory.getAmountsIn(outOneFLUX, path);
        //amounts[0]= usdt amount , amounts[1]= flux amount 1e18
        return (amounts[0] * 1e8) / (10**usdDecimals);
    }

    function finalize() external {
        require(msg.sender == admin, "caller is not admin");
        selfdestruct(msg.sender);
    }
}
