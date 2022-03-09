pragma solidity =0.6.6;

import "@openzeppelin/contracts/introspection/IERC165.sol";
import "./ERC223/IERC223Recipient.sol";
import "./IPoolAgent.sol";
import "./IPoolApprover.sol";
import "./IPoolBackend.sol";
import "./IPoolCustomer.sol";
import "./IPoolFunding.sol";
import "./IPoolInternal.sol";
import "./IPoolManager.sol";
import "./IPoolOwner.sol";

interface IPool is IERC165, IERC223Recipient, IPoolAgent, IPoolApprover, IPoolBackend, IPoolCustomer, IPoolFunding, IPoolInternal, IPoolManager, IPoolOwner {}
