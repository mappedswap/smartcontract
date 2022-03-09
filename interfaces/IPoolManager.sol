pragma solidity =0.6.6;

import "./IPoolCustomerUpdate.sol";
import "./IPoolTokenPairInfo.sol";

interface IPoolManager is IPoolCustomerUpdate, IPoolTokenPairInfo {
    function addToken(
        string calldata tokenName,
        IERC20 tokenAddr,
        uint256 interestRate
    ) external;

    function getAgents() external view returns (address[] memory);

    function grantAgent(address agentAddr) external;

    function revokeAgent(address agentAddr) external;

    function updateTokenInterestRate(string calldata tokenName, uint256 newInterestRate) external;

    function updateTokenEffectiveDecimal(string calldata tokenName, uint256 newEffectiveDecimal) external;

    function removeToken(string calldata tokenName) external;

    function addPair(string calldata tokenAName, string calldata tokenBName) external;

    function updatePairEnableStatus(string calldata pairName, bool newEnableStatus) external;

    function removePair(string calldata pairName) external;

    event UpdateTokenInterestRate(string tokenName, uint256 oldInterestRate, uint256 oldEffectiveTime, uint256 newInterestRate, uint256 newEffectiveTime);

    event UpdateTokenEffectiveDecimal(string tokenName, uint256 oldEffectiveDecimal, uint256 newEffectiveDecimal);

    event UpdatePairEnableStatus(string pairName, bool oldEnableStatus, bool newEnableStatus);
}
