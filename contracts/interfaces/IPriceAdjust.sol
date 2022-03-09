pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IOwnable.sol";
import "./IPoolCustomer.sol";

interface IPriceAdjust is IOwnable {
    function initialize(IPoolCustomer _pool) external;

    function getPool() external view returns (address);

    function setPool(IPoolCustomer poolAddr) external;

    function adjust(
        string calldata tokenName,
        ERC20 tokenAddr,
        int256 targetPrice,
        uint8 decimals
    ) external;

    function topUp(ERC20 tokenAddr, uint256 amount) external;

    function withdraw(string calldata tokenName, uint256 amount) external;

    function getBackends() external view returns (address[] memory);

    function getManagers() external view returns (address[] memory);

    function grantBackend(address backendAddr) external;

    function grantManager(address managerAddr) external;

    function revokeBackend(address backendAddr) external;

    function revokeManager(address managerAddr) external;
}
