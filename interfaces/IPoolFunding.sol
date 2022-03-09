pragma solidity =0.6.6;

interface IPoolFunding {
    function addPoolFunding(string calldata tokenName, uint256 amount) external;

    function addPoolCompensation(uint256 amount) external;

    function getCumulativeLoss() external view returns (uint256);

    function getCumulativeCompensation() external view returns (uint256);
}
