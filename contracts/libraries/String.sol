pragma solidity =0.6.6;

library String {
    function equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function hashEquals(string memory a, bytes32 keccak256Hash) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256Hash;
    }
}
