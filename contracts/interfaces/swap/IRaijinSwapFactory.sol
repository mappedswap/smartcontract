pragma solidity =0.6.6;

import "../IOwnable.sol";
import "./IRaijinSwapLiquidityAllowance.sol";
import "./IUniswapV2Factory.sol";

interface IRaijinSwapFactory is IOwnable, IUniswapV2Factory, IRaijinSwapLiquidityAllowance {
    function getRouter() external view returns (address);

    function setRouter(address _router) external;
}
