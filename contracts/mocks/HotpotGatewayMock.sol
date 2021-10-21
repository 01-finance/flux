// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import { ERC20Mock } from "./ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INormalERC20 } from "../market/Interface.sol";

contract HotpotGatewayMock {
    address public vault;
    address public token;
    address public targetToken;

    constructor(
        address _vault,
        address _token,
        address _targetToken
    ) public {
        vault = _vault;
        token = _token;
        targetToken = _targetToken;
    }
}

contract HotpotRouterMock {
    address public flux;
    uint64 public sourceChainId;

    constructor(address _flux, uint64 _sourceChainId) public {
        flux = _flux;
        sourceChainId = _sourceChainId;
    }

    function crossTransfer(
        address gate,
        address to,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable {
        crossTransfer(gate, to, amount, maxFluxFee, new bytes(0));
    }

    function crossTransfer(
        address gate,
        address to,
        uint256 amount,
        uint256 maxFluxFee,
        bytes memory data
    ) public payable {
        if (maxFluxFee > 0) {
            IERC20(flux).transferFrom(msg.sender, address(this), (maxFluxFee * 9) / 10);
        }

        address sourceToken = HotpotGatewayMock(gate).token();
        IERC20(sourceToken).transferFrom(msg.sender, address(this), amount);

        // 立即执行跨链调用
        address token = HotpotGatewayMock(gate).targetToken();
        uint256 targetAmount = _toNativeAmount(token, _toMetaAmount(sourceToken, amount));
        uint256 fee = maxFluxFee == 0 ? (targetAmount * 3) / 1000 : 0;
        uint256 realAmount = targetAmount - fee;

        ERC20Mock(token).mint(to, realAmount);
        if (data.length > 0) {
            // 94904766  =>  hotpotCallback(uint64,address,uint256,bytes)
            // function hotpotCallback(uint64 sourceChainId,address sourceAddress,address token,uint256 amount,bytes calldata data);

            (bool success, ) = to.call{ value: 0 }(abi.encodeWithSelector(0x94904766, sourceChainId, msg.sender, token, realAmount, data));
            require(success, "call hotpotCallback method failed");
        }
    }

    function _toMetaAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 tokenDecimals = INormalERC20(token).decimals();
        return amount * (10**(18 - uint256(tokenDecimals))); //ignore check
    }

    function _toNativeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 tokenDecimals = INormalERC20(token).decimals();
        return amount / (10**(18 - uint256(tokenDecimals))); //ignore check
    }
}
