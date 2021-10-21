// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";

import { INormalERC20 } from "../market/Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

interface ILPHelper {
    /**
     * @notice 获取LP所对应的底层资产数量
     */
    function getTokenAmount(address lpToken, address holder)
        external
        view
        returns (
            address token0,
            uint256 amount0,
            address token1,
            uint256 amount1
        );

    function getTokenPrice(address[] calldata path) external view returns (uint256 price);
}

interface ISwapRouter {
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface ISwapPair {
    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract NoramlSwapTokenPairHelper is Ownable, Initializable {
    using SafeMath for uint256;

    ISwapRouter public router;

    function initialize(address admin, ISwapRouter _router) public initializer {
        require(admin != address(0), "admin is empty");
        require(address(_router) != address(0), "routner is emtpy");
        initOwner(admin);
        router = _router;
    }

    function setRouter(ISwapRouter _router) external onlyOwner {
        require(address(_router) != address(0), "routner is emtpy");
        router = _router;
    }

    /**
     * @notice 获取LP所对应的底层资产数量
     */
    function getTokenAmount(address pair, address user)
        external
        view
        returns (
            address token0,
            uint256 amount0,
            address token1,
            uint256 amount1
        )
    {
        ISwapPair tokenPair = ISwapPair(pair);
        token0 = tokenPair.token0(); // gas savings
        token1 = tokenPair.token1(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(pair);
        uint256 balance1 = IERC20(token1).balanceOf(pair);
        uint256 liquidity = tokenPair.balanceOf(user);
        uint256 totalSupply = tokenPair.totalSupply();
        amount0 = totalSupply == 0 ? 0 : liquidity.mul(balance0) / totalSupply;
        amount1 = totalSupply == 0 ? 0 : liquidity.mul(balance1) / totalSupply;
    }

    /**
     * @notice 计算买入 1个 path[last] 所对应的  path[0] token 数量。
     * @dev  path=[usdt,flux] 则表示计算出买入 1个 flux 所对应的  usdt
     */
    function getTokenPrice(address[] calldata path) external view returns (uint256 price) {
        require(address(router) != address(0), "router is empty");
        uint256 inputUnits = 10**(uint256(INormalERC20(path[0]).decimals()));
        uint256 outputUnits = 10**(uint256(INormalERC20(path[path.length - 1]).decimals()));
        uint256[] memory amounts = router.getAmountsIn(outputUnits, path);
        return amounts[0].mul(1e18).div(inputUnits);
    }
}
