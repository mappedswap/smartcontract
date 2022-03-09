pragma solidity =0.6.6;

import "../IOwnable.sol";
import "./IRaijinSwapLiquidityAllowance.sol";
import "./IUniswapV2Router02.sol";

interface IRaijinSwapRouter is IOwnable, IUniswapV2Router02, IRaijinSwapLiquidityAllowance {
    function getManagers() external view returns (address[] memory);

    function getSelectedLiquidityProviders() external view returns (address[] memory);

    function getSelectedSwappers() external view returns (address[] memory);

    function grantManager(address addr) external;

    function grantSelectedLiquidityProvider(address addr) external;

    function grantSelectedSwapper(address addr) external;

    function revokeManager(address addr) external;

    function revokeSelectedLiquidityProvider(address addr) external;

    function revokeSelectedSwapper(address addr) external;

    function isTokenRestricted(address token) external view returns (bool);

    function setTokenRestrictStatus(address token, bool restricted) external;

    function isSwapAllowed(address[] calldata path, address from) external view returns (bool);

    function pairFor(address tokenA, address tokenB) external view returns (address);
}
