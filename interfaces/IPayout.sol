pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "../libraries/PayoutStruct.sol";
import "./IOwnable.sol";

interface IPayout is IOwnable {
    function initialize() external;

    function getNextRoundID() external view returns (uint256);

    function getRoundSummary(uint256 roundID) external view returns (PayoutStruct.RoundSummary memory);

    function verify(
        uint256 roundID,
        address agentAddr,
        address[] calldata tokenList,
        uint256[] calldata amountList
    ) external view returns (bool);

    function isClaimed(uint256 roundID, address agentAddr) external view returns (bool);

    function create() external returns (uint256 roundID);

    function update(
        uint256 roundID,
        address[] calldata tokenList,
        PayoutStruct.AgentPayoutInput[] calldata agentPayoutList
    ) external;

    function updateFinish(uint256 roundID, address verifier) external;

    function verifyFinish(uint256 roundID) external;

    function approve(uint256 roundID, address verifier) external;

    function claim(
        uint256 roundID,
        address[] calldata tokenList,
        uint256[] calldata amountList
    ) external;

    function claimFor(
        uint256 roundID,
        address recipient,
        address[] calldata tokenList,
        uint256[] calldata amountList
    ) external;

    function revoke(uint256 roundID) external;

    event Created(uint256 roundID, address creator);

    event UpdateFinished(uint256 roundID, address creator, address verifier);

    event Verified(uint256 roundID, address verifier);

    event Approved(uint256 roundID, address approver);

    event Claimed(uint256 roundID, address recipient, address[] tokenList, uint256[] amountList);

    event Revoked(uint256 roundID, address approver);
}
