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

    function stakeToken(IERC20 tokenAddr, uint256 amount) external;

    function requestRedemption(IERC20 tokenAddr, uint256 amount) external;

    function redeemToken(IERC20 tokenAddr) external;

    function getPoolStaked(IERC20 tokenAddr) external view returns (uint256);

    function getUserStaked(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserRequestedToRedeem(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserCanRedeemNow(IERC20 tokenAddr, address userAddr) external view returns (uint256);

    function getUserRedemptionDetails(IERC20 tokenAddr, address userAddr) external view returns (RedemptionInfo[] memory);

    event StakeToken(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    event RequestRedemption(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    event RedeemToken(address indexed tokenAddr, address indexed userAddr, uint256 amount);

    struct RedemptionInfo {
        uint256 amount;
        uint64 requestTime;
    }
}
