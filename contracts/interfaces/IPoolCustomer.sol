pragma solidity =0.6.6;

import "./IPoolCustomerInfo.sol";
import "./IPoolTokenPairInfo.sol";
import "./IPoolTrading.sol";

interface IPoolCustomer is IPoolCustomerInfo, IPoolTokenPairInfo, IPoolTrading {}
