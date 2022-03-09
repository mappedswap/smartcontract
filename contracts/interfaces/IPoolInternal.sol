pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./swap/IRaijinSwapRouter.sol";

interface IPoolInternal {
    function initialize(
        IRaijinSwapRouter _router,
        IERC20 _refToken,
        uint256 _interestInterval
    ) external;

    function getDeployers() external view returns (address[] memory);

    function grantDeployer(address deployerAddr) external;

    function revokeDeployer(address deployerAddr) external;

    function getManagementContract() external view returns (address c);

    function setManagementContract(address newManagementContract) external;
}
