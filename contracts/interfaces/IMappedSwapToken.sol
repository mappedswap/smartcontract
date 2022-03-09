pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC223/IERC223.sol";
import "./IOwnable.sol";

interface IMappedSwapToken is IOwnable, IERC20, IERC223 {
    function totalSupply() external view override(IERC20, IERC223) returns (uint256);

    function balanceOf(address account) external view override(IERC20, IERC223) returns (uint256);

    function transfer(address recipient, uint256 amount) external override(IERC20, IERC223) returns (bool);

    function getMinters() external view returns (address[] memory);

    function getBurners() external view returns (address[] memory);

    function grantMinter(address minterAddr) external;

    function grantBurner(address burnerAddr) external;

    function revokeMinter(address minterAddr) external;

    function revokeBurner(address burnerAddr) external;

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}
