pragma solidity =0.6.6;

import "@openzeppelin/contracts/proxy/UpgradeableProxy.sol";

contract OwnedUpgradeableProxy is UpgradeableProxy {
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event AdminChanged(address previousAdmin, address newAdmin);

    modifier ifAdmin() {
        if (msg.sender == admin()) {
            _;
        } else {
            _fallback();
        }
    }

    constructor(address _logic, bytes memory _data) public payable UpgradeableProxy(_logic, _data) {
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        emit AdminChanged(address(0), msg.sender);
        _setAdmin(msg.sender);
    }

    function admin() public view returns (address adm) {
        bytes32 slot = _ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function implementation() public view returns (address implementation_) {
        implementation_ = _implementation();
    }

    function changeAdmin(address newAdmin) external virtual ifAdmin {
        require(newAdmin != address(0), "OwnedUpgradeableProxy: new admin is the zero address");
        emit AdminChanged(admin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function upgradeTo(address newImplementation) external virtual ifAdmin {
        _upgradeTo(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable virtual ifAdmin {
        _upgradeTo(newImplementation);
        Address.functionDelegateCall(newImplementation, data);
    }

    function _setAdmin(address newAdmin) private {
        bytes32 slot = _ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }
}
