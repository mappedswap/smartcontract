pragma solidity =0.6.6;

import "./IPoolCustomerInfo.sol";
import "./IPoolCustomerUpdate.sol";

interface IPoolAgent is IPoolCustomerInfo, IPoolCustomerUpdate {}
