pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "../libraries/PoolStruct.sol";

interface IPoolCustomerInfo {
    function getRouter() external view returns (address);

    function getReferenceToken() external view returns (address);

    function getCustomerInfo(address customer) external view returns (PoolStruct.CustomerInfo memory);
}
