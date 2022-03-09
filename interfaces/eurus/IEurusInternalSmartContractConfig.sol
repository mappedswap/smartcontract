pragma solidity =0.6.6;

interface IEurusInternalSmartContractConfig {
    function setMainnetWalletAddress(address addr) external;

    function setUserWalletAddress(address addr) external;

    function setInnetWalletAddress(address addr) external;

    function setExternalSCConfigAddress(address addr) external;

    function setAdminFeeWalletAddress(address addr) external;

    function setWalletAddressMap(address addr) external;

    function setApprovalWalletAddress(address addr) external;

    function setWithdrawSmartContract(address addr) external;

    function setUserWalletProxyAddress(address addr) external;

    function setMarketingRegWalletAddress(address addr) external;

    function setCentralizedGasFeeAdjustment(uint256 gasFee) external;

    function getInnetPlatformWalletAddress() external view returns (address);

    function getMainnetPlatformWalletAddress() external view returns (address);

    function getApprovalWalletAddress() external view returns (address);

    function getExternalSCConfigAddress() external view returns (address);

    function getWalletAddressMap() external view returns (address);

    function getWithdrawSmartContract() external view returns (address);

    function getAdminFeeWalletAddress() external view returns (address);

    function getUserWalletAddress() external view returns (address);

    function getUserWalletProxyAddress() external view returns (address);

    function getErc20SmartContractAddrByAssetName(string calldata asset) external view returns (address);

    function setGasFeeWalletAddress(address addr) external;

    function getGasFeeWalletAddress() external view returns (address);

    function getMarketingRegWalletAddress() external view returns (address);

    function getCentralizedGasFeeAdjustment() external view returns (uint256);
}
