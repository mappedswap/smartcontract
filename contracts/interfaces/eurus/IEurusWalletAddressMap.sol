pragma solidity =0.6.6;

interface IEurusWalletAddressMap {
    function setWalletInfo(
        address walletAddress,
        string calldata key,
        string calldata value
    ) external;

    function addWalletInfo(
        address walletAddress,
        string calldata email,
        bool isMerchant,
        bool isMetaMask
    ) external;

    function removeWalletInfo(address walletAddress) external;

    function isWalletAddressExist(address addr) external view returns (bool);

    function isMerchantWallet(address addr) external view returns (bool);

    function getWalletInfoList() external view returns (address[] memory);

    function getWalletInfoValue(address addr, string calldata field) external view returns (string memory);

    function getLastUpdateTime(address walletAddress) external view returns (int256);

    function setLastUpdateTime(address walletAddress, int256 time) external;
}
