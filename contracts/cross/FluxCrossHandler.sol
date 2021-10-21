// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import "../lib/Ownable.sol";
import { INormalERC20 } from "../market/Interface.sol";
import { IFluxCross, ICrossRouter, ICrossRouterWithData, ICrossMarket, IHotpotGateway } from "./Interface.sol";
import { SafeMath } from "../lib/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

contract FluxCrossHandler is IFluxCross, Initializable, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event CrossDeposit(address indexed to, address indexed token, bool isTransfer, uint256 crossAmount, uint256 amount);

    uint8 private constant MSG_VERSION = 0x1;
    uint8 private constant META_DECIMALS = 18;

    address public hotpotRouter;
    IERC20 public fluxToken;
    address public hotpotCaller;

    // chain config: chainId => ( token => [gateway,vault] )
    mapping(uint64 => mapping(address => address[2])) public hotpotGatewayInfo;
    // FluxCrossHandler contract at all chains.
    mapping(uint64 => address) public crossWhitelist;
    // token market:  token => ftoken.
    mapping(address => ICrossMarket) public fluxMarkets;
    // min cross transfer amount :  token => min amount.
    mapping(address => uint256) public minAmountLimit;

    modifier onlyFMarketOrAdmin(address token) {
        require(address(fluxMarkets[token]) == msg.sender || msg.sender == owner(), "ONLY_FOR_FLUXMARKET");
        _;
    }

    function initialize(
        address admin,
        IERC20 _fluxToken,
        address _hotpotCaller,
        address _hotpotRouter
    ) external initializer {
        initOwner(admin);
        require(_hotpotCaller != address(0), "ADDRESS_IS_EMPTY");
        require(_hotpotRouter != address(0), "ADDRESS_IS_EMPTY");
        require(address(_fluxToken) != address(0), "ADDRESS_IS_EMPTY");
        hotpotCaller = _hotpotCaller;
        hotpotRouter = _hotpotRouter;
        fluxToken = _fluxToken;
    }

    function setHotpotCaller(address _hotpotCaller) external onlyOwner {
        require(_hotpotCaller != address(0), "ADDRESS_IS_EMPTY");
        hotpotCaller = _hotpotCaller;
    }

    function setHotpotRouter(address _hotpotRouter) external onlyOwner {
        require(address(_hotpotRouter) != address(0), "ADDRESS_IS_EMPTY");
        hotpotRouter = _hotpotRouter;
    }

    /**
      @notice set hotpot config
      @param gateways from hotpot
     */
    function setHotpotConfig(uint64 chainId, IHotpotGateway[] calldata gateways) external onlyOwner {
        for (uint256 i = 0; i < gateways.length; i++) {
            IHotpotGateway gw = gateways[i];
            address[2] memory items;
            items[0] = address(gateways[i]);
            items[1] = gateways[i].vault();
            hotpotGatewayInfo[chainId][gw.token()] = items;
            // ignore event
        }
    }

    function clearHotpotConfig(uint64 chainId, address token) external onlyOwner {
        delete hotpotGatewayInfo[chainId][token];
        // ignore event
    }

    function setCrossWhitelist(uint64[] calldata chains, address[] calldata handlers) external onlyOwner {
        require(chains.length == handlers.length, "INVALID_LEN");
        for (uint256 i = 0; i < handlers.length; i++) {
            require(handlers[i] != address(0), "ADDRESS_IS_EIMPTY");
            crossWhitelist[chains[i]] = handlers[i];
            // ignore event
        }
    }

    function setCrossMinAmount(address[] calldata tokens, uint256[] calldata amounts) external onlyOwner {
        require(tokens.length == amounts.length, "INVALID_LEN");
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "ADDRESS_IS_EIMPTY");
            minAmountLimit[tokens[i]] = amounts[i];
            // ignore event
        }
    }

    function setftoken(address[] calldata tokens, ICrossMarket[] calldata ftokens) external onlyOwner {
        require(tokens.length == ftokens.length, "INVALID_LEN");
        for (uint256 i = 0; i < ftokens.length; i++) {
            require(tokens[i] != address(0), "ADDRESS_IS_EIMPTY");
            require(address((ftokens)[i]) != address(0), "ADDRESS_IS_EIMPTY");
            fluxMarkets[tokens[i]] = ftokens[i];
            // ignore event
        }
    }

    /**
      @notice call cross-chain deposit to given chain.
     */
    function deposit(
        uint64 tragetChainId,
        address from,
        address token,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable override onlyFMarketOrAdmin(token) {
        require(tx.origin == from, "ONLY_EOA_YOURSELF");
        _cross(tragetChainId, from, token, amount, maxFluxFee, true);
    }

    /**
      @notice call cross-chain withdraw to given wallet at other chain.
     */
    function withdraw(
        uint64 tragetChainId,
        address from,
        address token,
        uint256 amount,
        uint256 maxFluxFee
    ) external payable override onlyFMarketOrAdmin(token) {
        require(tx.origin == from, "ONLY_EOA_YOURSELF");
        _cross(tragetChainId, from, token, amount, maxFluxFee, false);
    }

    /**
     * @notice wait hotpot call me.(the method name must be `hotpotCallback`)
     * @param sourceChainId  cross-chain source chain
     * @param source  source chain contract(FluxCrossHandler).
     * @param token  cross-chain transfer token at current chain.
     * @param amount cross-chain transfer token amount except fee.
     * @param data cross-chain transfer message.
     */
    function hotpotCallback(
        uint64 sourceChainId,
        address source,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        // msg.sender must be address of hotpot protocol.
        require(hotpotCaller == msg.sender, "YOU_ARE_NOT_HOTPOT");

        // decode message
        (uint8 ver, address to, uint256 totalMetaAmount) = abi.decode(data, (uint8, address, uint256));

        // safe check
        require(ver == MSG_VERSION, "INVALID_VERSION");
        require(crossWhitelist[sourceChainId] == source, "NON-WHITELIST");

        bool success;
        if (amount > 0) {
            // deposit to  flux for to.
            ICrossMarket mkt = fluxMarkets[token];
            IERC20(token).approve(address(mkt), amount);
            // try deposit to flux, will transfer token to to if failed.
            (success, ) = address(mkt).call(abi.encodeWithSelector(mkt.depositFor.selector, to, amount));
            if (!success) IERC20(token).safeTransfer(to, amount);
        } else {
            success = true;
        }
        emit CrossDeposit(to, token, !success, _toNativeAmount(token, totalMetaAmount), amount);
        return true;
    }

    function _cross(
        uint64 tragetChainId,
        address from,
        address token,
        uint256 amount,
        uint256 maxFluxFee,
        bool needCallBack
    ) private {
        require(amount >= minAmountLimit[token], "CROSS_AMOUNT_TO_SAMLL");

        address[2] memory info = hotpotGatewayInfo[tragetChainId][token];
        address gateway = info[0];
        address vault = info[1];
        require(gateway != address(0), "GATEWAY_NOT_FOUND");
        require(vault != address(0), "VAULT_NOT_FOUND");

        // approve token to hotpot vault
        IERC20(token).approve(vault, amount);
        // approve FLUXToken
        bool useFLUXPay = maxFluxFee > 0;

        // get FLUX token from `from`.
        if (useFLUXPay) {
            fluxToken.safeTransferFrom(from, address(this), maxFluxFee);
            fluxToken.approve(vault, maxFluxFee);
        }

        if (needCallBack) {
            address tragetHandler = crossWhitelist[tragetChainId];
            require(tragetHandler != address(0), "HANDLER_NOT_FOUND");
            // call back data = {MSG_VERSION,Receiver,Amount,FluxCrossHandler}
            bytes memory data = abi.encode(MSG_VERSION, from, _toMetaAmount(token, amount));
            ICrossRouterWithData(hotpotRouter).crossTransfer{ value: msg.value }(gateway, tragetHandler, amount, maxFluxFee, data);
        } else {
            ICrossRouter(hotpotRouter).crossTransfer{ value: msg.value }(gateway, from, amount, maxFluxFee);
        }
        // return the remaing FLUX token to `from`.
        if (useFLUXPay) {
            uint256 remain = fluxToken.balanceOf(address(this));
            if (remain > 0) fluxToken.safeTransfer(from, remain);
        }
    }

    /**
      @dev 将 token 数量转换为 18 精度
     */
    function _toMetaAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 tokenDecimals = INormalERC20(token).decimals();
        return amount.mul(10**uint256(META_DECIMALS - tokenDecimals)); //ignore check
    }

    /**
      @dev 将 token 数量从 18 精度还原成实际精度
     */
    function _toNativeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 tokenDecimals = INormalERC20(token).decimals();
        return amount.div(10**uint256(META_DECIMALS - tokenDecimals)); //ignore check
    }
}
