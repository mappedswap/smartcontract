pragma solidity =0.6.6;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IAgentData.sol";

contract AgentData is OwnableUpgradeable, AccessControlUpgradeable, IAgentData {
    bytes32 private constant INSERTER_ROLE = keccak256("INSERTER_ROLE");
    bytes32 private constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 private constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    mapping(address => bytes32) private hashes;

    mapping(address => bytes32) private proposals;

    function initialize() public override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function owner() public view override(OwnableUpgradeable, IOwnable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    function renounceOwnership() public override(OwnableUpgradeable, IOwnable) {
        address _owner = owner();
        OwnableUpgradeable.renounceOwnership();
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function transferOwnership(address newOwner) public override(OwnableUpgradeable, IOwnable) {
        address _owner = owner();
        require(_owner != newOwner, "Ownable: self ownership transfer");

        OwnableUpgradeable.transferOwnership(newOwner);
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function verifyData(address agentAddr, bytes calldata data) external view override returns (bool) {
        return hashes[agentAddr] == getHash(agentAddr, data);
    }

    function insertData(address agentAddr, bytes calldata data) external override onlyInserter {
        require(hashes[agentAddr] == "", "Already inserted");
        require(data.length > 0, "Empty data");

        hashes[agentAddr] = getHash(agentAddr, data);
    }

    function updateData(address agentAddr, bytes calldata data) external override onlyUpdater {
        bytes32 current = hashes[agentAddr];
        bytes32 newHash = getHash(agentAddr, data);

        require(current != "", "Not inserted");
        require(current != newHash, "Update to same data");

        proposals[agentAddr] = newHash;
    }

    function approveData(address agentAddr, bytes calldata data) external override onlyApprover {
        bytes32 newHash = proposals[agentAddr];

        require(newHash == getHash(agentAddr, data), "Data not match");

        hashes[agentAddr] = newHash;
        proposals[agentAddr] = "";
    }

    function getHash(address agentAddr, bytes memory data) private pure returns (bytes32) {
        if (data.length == 0) {
            return "";
        }

        return keccak256(abi.encodePacked(agentAddr, data));
    }

    function getInserters() external view override returns (address[] memory) {
        return getMembers(INSERTER_ROLE);
    }

    function getUpdaters() external view override returns (address[] memory) {
        return getMembers(UPDATER_ROLE);
    }

    function getApprovers() external view override returns (address[] memory) {
        return getMembers(APPROVER_ROLE);
    }

    function grantInserter(address inserterAddr) external override onlyOwner {
        grantRole(INSERTER_ROLE, inserterAddr);
    }

    function grantUpdater(address updaterAddr) external override onlyOwner {
        grantRole(UPDATER_ROLE, updaterAddr);
    }

    function grantApprover(address approverAddr) external override onlyOwner {
        grantRole(APPROVER_ROLE, approverAddr);
    }

    function revokeInserter(address inserterAddr) external override onlyOwner {
        revokeRole(INSERTER_ROLE, inserterAddr);
    }

    function revokeUpdater(address updaterAddr) external override onlyOwner {
        revokeRole(UPDATER_ROLE, updaterAddr);
    }

    function revokeApprover(address approverAddr) external override onlyOwner {
        revokeRole(APPROVER_ROLE, approverAddr);
    }

    function getMembers(bytes32 role) private view returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    modifier onlyInserter() {
        require(hasRole(INSERTER_ROLE, msg.sender), "Inserter only");
        _;
    }

    modifier onlyUpdater() {
        require(hasRole(UPDATER_ROLE, msg.sender), "Updater only");
        _;
    }

    modifier onlyApprover() {
        require(hasRole(APPROVER_ROLE, msg.sender), "Approver only");
        _;
    }
}
