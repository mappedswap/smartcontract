pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IEurusExternalSmartContractConfig.sol";
import "./IEurusInternalSmartContractConfig.sol";

interface IEurusERC20 is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function submitWithdraw(
        address dest,
        uint256 withdrawAmount,
        uint256 amountWithFee
    ) external;

    function getInternalSCConfigAddress() external view returns (address);

    function setInternalSCConfigAddress(IEurusInternalSmartContractConfig addr) external;

    function getExternalSCConfigAddress() external view returns (address);

    function setExternalSCConfigAddress(IEurusExternalSmartContractConfig addr) external;

    function addBlackListDestAddress(address addr) external;

    function removeBlackListDestAddress(address addr) external;
}
