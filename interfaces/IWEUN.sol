pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWEUN is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function deposit() external payable;

    function depositTo(address recipient) external payable;

    function withdraw(uint256 amount) external;

    function withdrawTo(address payable recipient, uint256 amount) external;

    function withdrawFrom(
        address sender,
        address payable recipient,
        uint256 amount
    ) external;
}
