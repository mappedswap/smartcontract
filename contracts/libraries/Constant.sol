pragma solidity =0.6.6;

library Constant {
    bytes32 internal constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 internal constant APPROVER_ROLE = keccak256("APPROVER_ROLE");
    bytes32 internal constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 internal constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 internal constant DEFAULT_EFFECTIVE_DECIMAL = 6;
    string internal constant REF_TOKEN_NAME = "USDM";

    bytes32 internal constant MANAGEMENT_CONTRACT_SLOT = bytes32(uint256(keccak256("pool.proxy.management")) - 1);

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
}
