pragma solidity 0.6.8;
import "./Test.sol";
import "../market/Market.sol";

abstract contract TestMarketMock is Market {
    function _initialize(
        address guard_,
        address oracle_,
        address interestRateModel_,
        address underlying_,
        string memory name_,
        string memory symbol_
    ) internal {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        interestIndex = 1e18; //设置为最小值
        initialExchangeRateMan = 1e18;
        lastAccrueInterest = block.timestamp;

        underlying = IERC20(underlying_);
        guard = Guard(guard_);
        app = FluxApp(guard.flux());
        oracle = IPriceOracle(oracle_);
        interestRateModel = IRModel(interestRateModel_);
        //set admin
        initOwner(guard.owner());
        //safe check
        underlyingPrice();
        app.IS_FLUX();
        getBorrowRate();
    }
}
