pragma solidity =0.6.6;

import "./IOwnable.sol";

interface IAgentData is IOwnable {
    function initialize() external;

    function verifyData(address agentAddr, bytes calldata data) external view returns (bool);

    function insertData(address agentAddr, bytes calldata data) external;

    function updateData(address agentAddr, bytes calldata data) external;

    function approveData(address agentAddr, bytes calldata data) external;

    function getInserters() external view returns (address[] memory);

    function getUpdaters() external view returns (address[] memory);

    function getApprovers() external view returns (address[] memory);

    function grantInserter(address inserterAddr) external;

    function grantUpdater(address updaterAddr) external;

    function grantApprover(address approverAddr) external;

    function revokeInserter(address inserterAddr) external;

    function revokeUpdater(address updaterAddr) external;

    function revokeApprover(address approverAddr) external;
}
