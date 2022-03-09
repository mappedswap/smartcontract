pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol";
import "./interfaces/IStaking.sol";

contract Staking is OwnableUpgradeable, ERC165Upgradeable, IStaking {
    using SafeMath for uint256;

    bytes4 private constant ERC1363RECEIVER_RETURN = bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"));
    uint8 private constant NOT_ENTERED = 1;
    uint8 private constant ENTERED = 2;

    struct User {
        uint256 staked;
        uint112 start;
        uint112 last;
    }

    struct RedemptionNode {
        uint256 amount;
        uint64 requestTime;
        uint112 next;
    }

    mapping(address => bool) private stakeable;

    mapping(address => uint256) private poolStaked;

    mapping(address => mapping(address => User)) private users;

    mapping(uint112 => RedemptionNode) private redemptionNodes;

    uint8 private directStaking;

    uint112 private nextNodeID;

    uint64 private redeemWaitPeriod;

    function initialize(uint64 _redeemWaitPeriod) external override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ERC165_init_unchained();

        directStaking = NOT_ENTERED;
        nextNodeID = 1;
        redeemWaitPeriod = _redeemWaitPeriod;

        IStaking i;
        _registerInterface(i.tokenReceived.selector);
        _registerInterface(i.onTokenTransfer.selector);
        _registerInterface(i.onTransferReceived.selector);
    }

    function owner() public view override(OwnableUpgradeable, IOwnable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    function renounceOwnership() public override(OwnableUpgradeable, IOwnable) {
        OwnableUpgradeable.renounceOwnership();
    }

    function transferOwnership(address newOwner) public override(OwnableUpgradeable, IOwnable) {
        address _owner = owner();
        require(_owner != newOwner, "Ownable: self ownership transfer");

        OwnableUpgradeable.transferOwnership(newOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165Upgradeable, IERC165) returns (bool) {
        return ERC165Upgradeable.supportsInterface(interfaceId);
    }

    function tokenReceived(
        address from,
        uint256 amount,
        bytes calldata
    ) external override {
        if (directStaking != ENTERED) {
            stake(msg.sender, from, amount);
        }
    }

    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata
    ) external override returns (bool) {
        if (directStaking != ENTERED) {
            stake(msg.sender, from, amount);
        }

        return true;
    }

    function onTransferReceived(
        address,
        address from,
        uint256 value,
        bytes calldata
    ) external override returns (bytes4) {
        if (directStaking != ENTERED) {
            stake(msg.sender, from, value);
        }

        return ERC1363RECEIVER_RETURN;
    }

    function isTokenStakeable(IERC20 tokenAddr) external view override returns (bool) {
        return stakeable[address(tokenAddr)];
    }

    function setTokenStakeability(IERC20 tokenAddr, bool stakeability) external override onlyOwner {
        stakeable[address(tokenAddr)] = stakeability;
    }

    function getRedeemWaitPeriod() external view override returns (uint64) {
        return redeemWaitPeriod;
    }

    function setRedeemWaitPeriod(uint64 newRedeemWaitPeriod) external override onlyOwner {
        redeemWaitPeriod = newRedeemWaitPeriod;
    }

    function stakeToken(IERC20 tokenAddr, uint256 amount) external override {
        directStaking = ENTERED;
        require(tokenAddr.transferFrom(msg.sender, address(this), amount));
        directStaking = NOT_ENTERED;

        stake(address(tokenAddr), msg.sender, amount);
    }

    function stake(
        address tokenAddr,
        address from,
        uint256 amount
    ) private {
        require(stakeable[tokenAddr], "Token is not stakeable");
        require(from != address(0), "Invalid sender");
        require(amount > 0, "Invalid amount");

        // Simply update stake record
        poolStaked[tokenAddr] = poolStaked[tokenAddr].add(amount);
        users[tokenAddr][from].staked = users[tokenAddr][from].staked.add(amount);

        emit StakeToken(tokenAddr, from, amount);
    }

    function requestRedemption(IERC20 tokenAddr, uint256 amount) external override {
        address addr = address(tokenAddr);
        require(stakeable[addr], "Token is not stakeable");
        require(amount > 0, "Invalid amount");

        User storage ptr = users[addr][msg.sender];
        User memory user = ptr;

        //  Cannot redeem more than staked
        require(amount <= user.staked, "Token Staked is not enough");

        poolStaked[addr] = poolStaked[addr].sub(amount);
        ptr.staked = user.staked.sub(amount);

        // Create a node to repesnt this redemption
        uint112 nodeID;
        {
            nodeID = nextNodeID++;
            redemptionNodes[nodeID] = RedemptionNode(amount, uint64(block.timestamp), 0);
        }

        if (user.start == 0) {
            // If currently no other pending redemption, this node becomes first node
            ptr.start = nodeID;
        } else {
            // Append node to linked list
            redemptionNodes[user.last].next = nodeID;
        }

        ptr.last = nodeID;

        emit RequestRedemption(addr, msg.sender, amount);
    }

    function redeemToken(IERC20 tokenAddr) external override {
        address addr = address(tokenAddr);
        require(stakeable[addr], "Token is not stakeable");

        uint64 _redeemWaitPeriod = redeemWaitPeriod;
        uint256 amount = 0;

        User storage ptr = users[addr][msg.sender];
        User memory user = ptr;
        uint112 nodeID = user.start;

        while (nodeID != 0) {
            RedemptionNode memory node = redemptionNodes[nodeID];

            // Wait period still not passed, and because this list preserve the redemption order, no need to check following nodes
            if ((node.requestTime + _redeemWaitPeriod) > block.timestamp) {
                break;
            }

            // Node can be removed to return gas
            delete redemptionNodes[nodeID];
            amount = amount.add(node.amount);
            nodeID = node.next;
        }

        require(amount > 0, "No token can be redeemed");

        ptr.start = nodeID;

        if (nodeID == 0) {
            // All redemption requests are cleared, linked list become empty, also remove last value
            ptr.last = 0;
        }

        require(tokenAddr.transfer(msg.sender, amount));

        emit RedeemToken(addr, msg.sender, amount);
    }

    function getPoolStaked(IERC20 tokenAddr) external view override returns (uint256) {
        return poolStaked[address(tokenAddr)];
    }

    function getUserStaked(IERC20 tokenAddr, address userAddr) external view override returns (uint256) {
        return users[address(tokenAddr)][userAddr].staked;
    }

    function getUserRequestedToRedeem(IERC20 tokenAddr, address userAddr) external view override returns (uint256) {
        return sumRedemption(tokenAddr, userAddr, false);
    }

    function getUserCanRedeemNow(IERC20 tokenAddr, address userAddr) external view override returns (uint256) {
        return sumRedemption(tokenAddr, userAddr, true);
    }

    function sumRedemption(
        IERC20 tokenAddr,
        address userAddr,
        bool onlyCanRedeem
    ) private view returns (uint256) {
        uint64 _redeemWaitPeriod = redeemWaitPeriod;
        uint256 amount = 0;
        uint112 nodeID = users[address(tokenAddr)][userAddr].start;

        while (nodeID != 0) {
            RedemptionNode memory node = redemptionNodes[nodeID];

            if (onlyCanRedeem && ((node.requestTime + _redeemWaitPeriod) > block.timestamp)) {
                break;
            }

            amount = amount.add(node.amount);
            nodeID = node.next;
        }

        return amount;
    }

    function getUserRedemptionDetails(IERC20 tokenAddr, address userAddr) external view override returns (RedemptionInfo[] memory) {
        User memory user = users[address(tokenAddr)][userAddr];

        // Go through the linked list first to get node count
        // Because the count is only used in this view function, so not to save it in storage
        uint256 count;
        uint112 nodeID = user.start;

        while (nodeID != 0) {
            count++;
            nodeID = redemptionNodes[nodeID].next;
        }

        RedemptionInfo[] memory ret = new RedemptionInfo[](count);
        nodeID = user.start;

        for (uint256 i = 0; i < count; i++) {
            RedemptionNode memory n = redemptionNodes[nodeID];
            ret[i] = RedemptionInfo(n.amount, n.requestTime);
            nodeID = n.next;
        }

        return ret;
    }
}
