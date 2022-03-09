pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC223/IERC223Recipient.sol";
import "./ERC677/IERC677Recipient.sol";
import "./ERC1363/IERC1363Receiver.sol";
import "./IOwnable.sol";

interface IStaking is IOwnable, IERC165, IERC223Recipient, IERC677Recipient, IERC1363Receiver {
    function initialize(uint64 _redeemWaitPeriod) external;

    function isTokenStakeable(IERC20 tokenAddr) external view returns (bool);

    function setTokenStakeability(IERC20 tokenAddr, bool stakeability) external;

    function getRedeemWaitPeriod() external view returns (uint64);

    function setRedeemWaitPeriod(uint64 newRedeemWaitPeriod) external;

    function lockedStakingAdder() external view returns (address);

    function setLockedStakingAdder(address adderAddr) external;

    function stakeToken(IERC20 tokenAddr, uint256 amount) external;

    function addLockedStaking(
        IERC20 tokenAddr,
        address poolAddr,
        address userAddr,
        uint256 amount,
        uint64 stakeTime,
        uint64 nodeID,
        bytes32 stakeHash,
        uint64 unlockInterval,
        uint64 division
    ) external;

    function requestRedemption(IERC20 tokenAddr, uint256 amount) external;

    function redeemToken(IERC20 tokenAddr) external;

    function getPoolStaked(IERC20 tokenAddr) external view returns (uint256);

    function getUserStaked(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserStakingDetails(IERC20 tokenAddr, address userAddr) external view returns (StakingInfo[] memory);

    function getUserRequestedToRedeem(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserCanRedeemNow(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserRedemptionDetails(IERC20 tokenAddr, address userAddr) external view returns (RedemptionInfo[] memory);

    function deposit(IERC20 tokenAddr, uint256 amount) external;

    event StakeToken(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    event RequestRedemption(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    event RedeemToken(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    struct StakingInfo {
        uint256 initialStakeAmount;
        uint256 remainAmount;
        uint64 stakeTime;
        uint64 unlockInterval;
        uint64 division;
    }

    struct RedemptionInfo {
        uint256 amount;
        uint64 requestTime;
    }
}
