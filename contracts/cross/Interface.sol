// SPDX-License-Identifier: MIT
// Created by Flux Team
pragma solidity 0.6.8;

interface IFluxCross {
    function deposit(
        uint64 tragetChain,
        address receiver,
        address token,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable;

    function withdraw(
        uint64 tragetChain,
        address receiver,
        address token,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable;
}

interface IHotpotGateway {
    function vault() external view returns (address);

    function token() external view returns (address);
}

interface ICrossRouter {
    function crossTransfer(
        address gate,
        address to,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable;
}

interface ICrossRouterWithData {
    function crossTransfer(
        address gate,
        address to,
        uint256 amount,
        uint256 maxFluxFee,
        bytes calldata data
    ) external payable;
}

interface ICrossMarket {
    function depositFor(address receiver, uint256 amount) external;
}
