pragma solidity =0.6.6;

interface IERC223 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function standard() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event TransferData(bytes data);
}
