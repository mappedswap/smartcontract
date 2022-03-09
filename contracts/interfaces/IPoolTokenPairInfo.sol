pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "../libraries/PoolStruct.sol";

interface IPoolTokenPairInfo {
    function getTokenInfo(string calldata tokenName) external view returns (PoolStruct.Token memory);

    function getTokenInterestHistory(string calldata tokenName, int256 limit) external view returns (PoolStruct.InterestRate[] memory);

    function getAllTokens() external view returns (string[] memory);

    function getPairInfo(string calldata pairName) external view returns (PoolStruct.PairInfo memory);

    function getAllPairs() external view returns (string[] memory);
}
