pragma solidity =0.6.6;

interface IPoolApprover {
    function getAllowance(string calldata tokenName) external view returns (uint256);

    function updateAllowance(string calldata tokenName, uint256 newAllowance) external;
}
