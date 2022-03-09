pragma solidity =0.6.6;

interface IEurusApprovalWallet {
    function init(address internalSCConfig, uint8 queryPendingListLimit) external;

    function setInternalSmartContractConfig(address addr) external;

    function setQueryPendingListCount(uint8 limitCount) external;

    function setFallbackAddress(address addr) external;

    function getInternalSmartContractConfig() external view returns (address);

    function submitWithdrawRequest(
        address srcWallet,
        address destWallet,
        uint256 amount,
        string calldata assetName,
        uint256 feeAmount
    ) external returns (uint256);
}
