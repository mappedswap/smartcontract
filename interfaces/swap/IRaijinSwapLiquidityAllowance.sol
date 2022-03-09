pragma solidity =0.6.6;

interface IRaijinSwapLiquidityAllowance {
    function isLiquidityAllowed(
        address tokenA,
        address tokenB,
        address to
    ) external view returns (bool);
}
