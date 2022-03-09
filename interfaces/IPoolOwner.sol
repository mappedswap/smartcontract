pragma solidity =0.6.6;

import "./IOwnable.sol";

interface IPoolOwner is IOwnable {
    function getApprovers() external view returns (address[] memory);

    function getBackends() external view returns (address[] memory);

    function getManagers() external view returns (address[] memory);

    function grantApprover(address approverAddr) external;

    function grantBackend(address backendAddr) external;

    function grantManager(address managerAddr) external;

    function revokeApprover(address approverAddr) external;

    function revokeBackend(address backendAddr) external;

    function revokeManager(address managerAddr) external;
}
