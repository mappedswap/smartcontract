pragma solidity =0.6.6;

interface IPoolCustomerUpdate {
    function updateCustomerDetails(
        address customer,
        int256 newMode,
        uint256 newLeverage,
        uint256 newFunding,
        int256 newRiskLevel,
        int256 newStatus
    ) external;

    event UpdateMode(address indexed customer, int256 oldMode, int256 newMode);

    event UpdateLeverage(address indexed customer, uint256 oldLeverage, uint256 newLeverage);

    event UpdateFunding(address indexed customer, uint256 oldFunding, uint256 newFunding);

    event UpdateRiskLevel(address indexed customer, int256 oldRiskLevel, int256 newRiskLevel);

    event UpdateStatus(address indexed customer, int256 oldStatus, int256 newStatus);
}
