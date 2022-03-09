pragma solidity =0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "../interfaces/swap/IUniswapV2Factory.sol";
import "../interfaces/swap/IUniswapV2Pair.sol";
import "../interfaces/swap/IUniswapV2Router02.sol";
import "./PoolStruct.sol";
import "./String.sol";

library PoolUtilities {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using String for string;

    function nearestInterval(uint256 time, uint256 interval) internal pure returns (uint256) {
        return time.div(interval).mul(interval);
    }

    function tokenIndex(string[] storage tokenList, string memory tokenName) internal view returns (int256) {
        bytes32 tokenHash = keccak256(abi.encodePacked(tokenName));
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i].hashEquals(tokenHash)) {
                return int256(i);
            }
        }
        return -1;
    }

    function tokenExist(string[] storage tokenList, string memory tokenName) internal view returns (bool) {
        return tokenIndex(tokenList, tokenName) != -1;
    }

    function tokenMustExist(string[] storage tokenList, string memory tokenName) internal view {
        require(tokenExist(tokenList, tokenName), "Token not exist");
    }

    function pairIndex(string[] storage pairList, string memory pairName) internal view returns (int256) {
        bytes32 pairHash = keccak256(abi.encodePacked(pairName));
        for (uint256 i = 0; i < pairList.length; i++) {
            if (pairList[i].hashEquals(pairHash)) {
                return int256(i);
            }
        }
        return -1;
    }

    function pairExist(string[] storage pairList, string memory pairName) internal view returns (bool) {
        return pairIndex(pairList, pairName) != -1;
    }

    function pairMustExist(string[] storage pairList, string memory pairName) internal view {
        require(pairExist(pairList, pairName), "Pair not exist");
    }

    function copyInterestRates(
        PoolStruct.InterestRate[] memory dst,
        PoolStruct.InterestRate[] storage src,
        uint256 start,
        uint256 len
    ) internal view {
        uint256 pos = start;
        for (uint256 i = 0; i < len; i++) {
            dst[i] = src[pos];
            pos++;
        }
    }
}
