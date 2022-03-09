pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

interface IEurusExternalSmartContractConfig {
    function addCurrencyInfo(
        address _currencyAddr,
        string calldata asset,
        uint256 decimal,
        string calldata id
    ) external;

    function removeCurrencyInfo(string calldata asset) external;

    function getErc20SmartContractAddrByAssetName(string calldata asset) external view returns (address);

    function getErc20SmartContractByAddr(address _currencyAddr) external view returns (string memory);

    function getAssetAddress() external view returns (string[] memory, address[] memory);

    function getAssetDecimal(string calldata asset) external view returns (uint256);

    function getAssetListID(string calldata asset) external view returns (string memory);

    function setETHFee(
        uint256 ethFee,
        string[] calldata asset,
        uint256[] calldata amount
    ) external;

    function setAdminFee(string calldata asset, uint256 amount) external;

    function getAdminFee(string calldata asset) external view returns (uint256);

    function setKycLimit(
        string calldata asset,
        string calldata kycLevel,
        uint256 limit
    ) external;

    function getCurrencyKycLimit(string calldata symbol, string calldata kycLevel) external view returns (uint256);
}
