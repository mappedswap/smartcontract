pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
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

    struct LockedStakingUser {
        uint64 start;
        uint64 last;
    }

    struct LockedStakingNode {
        uint256 initialStakeAmount;
        uint256 remainAmount;
        uint64 stakeTime;
        uint64 unlockInterval;
        uint64 division;
        uint64 next;
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

    uint8 private directCalling;

    uint112 private nextNodeID;

    uint64 private redeemWaitPeriod;

    mapping(bytes32 => bool) private stakeHashes;

    mapping(address => mapping(address => LockedStakingUser)) private lockedStakingUsers;

    mapping(uint64 => LockedStakingNode) private lockedStakingNodes;

    uint64 private nextLockedStakingNodeID;

    address private _lockedStakingAdder;

    function initialize(uint64 _redeemWaitPeriod) external override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ERC165_init_unchained();

        directCalling = NOT_ENTERED;
        nextNodeID = 1;
        redeemWaitPeriod = _redeemWaitPeriod;
        nextLockedStakingNodeID = 1;

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
        if (directCalling != ENTERED) {
            stake(_msgSender(), from, amount);
        }
    }

    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata
    ) external override returns (bool) {
        if (directCalling != ENTERED) {
            stake(_msgSender(), from, amount);
        }

        return true;
    }

    function onTransferReceived(
        address,
        address from,
        uint256 value,
        bytes calldata
    ) external override returns (bytes4) {
        if (directCalling != ENTERED) {
            stake(_msgSender(), from, value);
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

    function lockedStakingAdder() external view override returns (address) {
        return _lockedStakingAdder;
    }

    function setLockedStakingAdder(address adderAddr) external override onlyOwner {
        _lockedStakingAdder = adderAddr;
    }

    function stakeToken(IERC20 tokenAddr, uint256 amount) external override skipTransferCallback {
        address sender = _msgSender();
        SafeERC20.safeTransferFrom(tokenAddr, sender, address(this), amount);
        stake(address(tokenAddr), sender, amount);
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
    ) external override onlyLockedStakingAdder {
        address addr = address(tokenAddr);

        // Basic checking
        require(stakeable[addr], "Token is not stakeable");
        require(amount > 0 && unlockInterval > 0 && division > 0, "Invalid parameter(s)");
        require(userAddr != address(0), "Address receiving the staking cannot be 0");

        // Every staking on Ethereum can produce an unique stakeHash, it can be used only once
        require(stakeHashes[stakeHash] == false, "This staking has been already added");
        stakeHashes[stakeHash] = true;

        // Verify the hash
        // However this cannot prove the staking is real, just to make sure input data is correct
        bytes32 verifyHash = keccak256(abi.encodePacked(poolAddr, userAddr, amount, stakeTime, nodeID));
        require(stakeHash == verifyHash, "The stakeHash is incorrect");

        // Update pool stake, note that this function does not require actual token transfer
        poolStaked[addr] = poolStaked[addr].add(amount);

        // Add a new node
        uint64 lockedStakingNodeID = newLockedStakingNode(amount, stakeTime, unlockInterval, division);

        LockedStakingUser storage ptr = lockedStakingUsers[addr][userAddr];
        LockedStakingUser memory user = ptr;

        if (user.start == 0) {
            ptr.start = lockedStakingNodeID;
        } else {
            lockedStakingNodes[user.last].next = lockedStakingNodeID;
        }

        ptr.last = lockedStakingNodeID;
    }

    function newLockedStakingNode(
        uint256 amount,
        uint64 stakeTime,
        uint64 unlockInterval,
        uint64 division
    ) private returns (uint64) {
        // Workaround of nextLockedStakingNodeID not initialized to 1
        uint64 lockedStakingNodeID;
        if (nextLockedStakingNodeID == 0) {
            lockedStakingNodeID = 1;
            nextLockedStakingNodeID = 2;
        } else {
            lockedStakingNodeID = nextLockedStakingNodeID++;
        }

        lockedStakingNodes[lockedStakingNodeID] = LockedStakingNode(amount, amount, stakeTime, unlockInterval, division, 0);
        return lockedStakingNodeID;
    }

    function redeemFromLockedStaking(
        address tokenAddr,
        address userAddr,
        uint256 maxRedeemAmount
    ) private returns (uint256) {
        LockedStakingUser storage ptr = lockedStakingUsers[tokenAddr][userAddr];
        LockedStakingUser memory user = ptr;

        // Deletion may occur during list traverse, so need the last nodeID
        uint64 nodeID = user.start;
        uint64 lastNodeID = 0;

        // Total amount can be redeemed from locked staking, must not larger than maxRedeemAmount
        uint256 redeemed = 0;

        while (nodeID != 0) {
            LockedStakingNode storage nodePtr = lockedStakingNodes[nodeID];
            LockedStakingNode memory node = nodePtr;

            // If nothing can be redeemed from this node, just move to the next one
            uint256 maxRedeemableFromNode = getRedeemableFromNode(node);
            if (maxRedeemableFromNode == 0) {
                lastNodeID = nodeID;
                nodeID = node.next;
                continue;
            }

            // The amount redeemed from this node can be fewer because of maxRedeemAmount bound
            // Find actual amount will be redeemed first
            uint256 willRedeemFromNode;
            bool breakLoop;
            if (redeemed.add(maxRedeemableFromNode) >= maxRedeemAmount) {
                willRedeemFromNode = maxRedeemAmount.sub(redeemed);
                breakLoop = true;
            } else {
                willRedeemFromNode = maxRedeemableFromNode;
                breakLoop = false;
            }
            redeemed = redeemed.add(willRedeemFromNode);

            // And after redeemed, if no more staking in this node, this node can be removed
            if (node.remainAmount == willRedeemFromNode) {
                // lastNodeID == 0 means current node is the first node
                // Deleting this node means update value in lockedStakingUsers
                if (lastNodeID == 0) {
                    ptr.start = node.next;
                } else {
                    lockedStakingNodes[lastNodeID].next = node.next;
                }

                delete lockedStakingNodes[nodeID];

                // In case of deleting the last node
                if (node.next == 0) {
                    ptr.last = lastNodeID;
                }

                if (breakLoop) {
                    break;
                }

                nodeID = node.next;
            } else {
                nodePtr.remainAmount = node.remainAmount.sub(willRedeemFromNode);

                if (breakLoop) {
                    break;
                }

                lastNodeID = nodeID;
                nodeID = node.next;
            }
        }

        return redeemed;
    }

    // Because unix time 0 1970-01-01 is Thursday, this offset makes the interval calculation start from every Monday
    uint256 private constant FOUR_DAYS = 4 days;

    function getRedeemableFromNode(LockedStakingNode memory node) private view returns (uint256) {
        // In case of finding redeemable amount of future staking
        if (node.stakeTime >= block.timestamp) {
            return 0;
        }

        // Find how many unlock intervals have been passed
        // Special handling for 7 days unlock interval, every interval is start from Monday 00:00:00 UTC
        // The first interval can be fewer than 7 days
        // For example, if stakeTime is at Friday 00:00:00 UTC, then 3 days later 1 interval will be passed
        uint256 baseTime;
        if (node.unlockInterval == 7 days) {
            baseTime = uint256(node.stakeTime).sub(FOUR_DAYS).div(7 days).mul(7 days).add(FOUR_DAYS);
        } else {
            baseTime = uint256(node.stakeTime);
        }

        uint256 intervalPassed = block.timestamp.sub(baseTime).div(node.unlockInterval);
        if (intervalPassed == 0) {
            return 0;
        }

        // The staking is fully unlocked, so the whole remain amount is redeemable
        if (intervalPassed >= node.division) {
            return node.remainAmount;
        }

        uint256 unlocked = node.initialStakeAmount.div(node.division).mul(intervalPassed);
        uint256 redeemed = node.initialStakeAmount.sub(node.remainAmount);

        // All unlocked staking are redeemed, so return 0
        if (redeemed >= unlocked) {
            return 0;
        }

        return unlocked.sub(redeemed);
    }

    function requestRedemption(IERC20 tokenAddr, uint256 amount) external override {
        address sender = _msgSender();
        address addr = address(tokenAddr);
        require(stakeable[addr], "Token is not stakeable");
        require(amount > 0, "Invalid amount");

        User storage ptr = users[addr][sender];
        User memory user = ptr;

        if (user.staked >= amount) {
            // If user free staking can cover the amount, redeem from it first to save gas for list iteration
            ptr.staked = user.staked.sub(amount);
        } else {
            uint256 remaining = amount.sub(user.staked);
            uint256 fromLockedStaking = redeemFromLockedStaking(addr, sender, remaining);
            require(remaining == fromLockedStaking, "Token Staked is not enough");
            ptr.staked = 0;
        }

        poolStaked[addr] = poolStaked[addr].sub(amount);

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

        emit RequestRedemption(addr, sender, amount);
    }

    function redeemToken(IERC20 tokenAddr) external override {
        address sender = _msgSender();
        address addr = address(tokenAddr);
        require(stakeable[addr], "Token is not stakeable");

        uint64 _redeemWaitPeriod = redeemWaitPeriod;
        uint256 amount = 0;

        User storage ptr = users[addr][sender];
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

        SafeERC20.safeTransfer(tokenAddr, sender, amount);

        emit RedeemToken(addr, sender, amount);
    }

    function getPoolStaked(IERC20 tokenAddr) external view override returns (uint256) {
        return poolStaked[address(tokenAddr)];
    }

    function getUserStaked(IERC20 tokenAddr, address userAddr) external view override returns (uint256) {
        address addr = address(tokenAddr);
        uint256 amount = 0;
        uint64 nodeID = lockedStakingUsers[addr][userAddr].start;

        while (nodeID != 0) {
            LockedStakingNode memory node = lockedStakingNodes[nodeID];
            amount = amount.add(node.remainAmount);
            nodeID = node.next;
        }

        return amount.add(users[addr][userAddr].staked);
    }

    function getUserStakingDetails(IERC20 tokenAddr, address userAddr) external view override returns (StakingInfo[] memory) {
        address addr = address(tokenAddr);
        uint256 count;
        uint64 start = lockedStakingUsers[addr][userAddr].start;
        uint64 nodeID = start;

        // Get the length of list
        while (nodeID != 0) {
            count++;
            nodeID = lockedStakingNodes[nodeID].next;
        }

        // Also add free staking as the first one, with 0 stakeTime and unlockInterval
        StakingInfo[] memory ret = new StakingInfo[](count + 1);
        uint256 freeStaking = users[addr][userAddr].staked;
        ret[0] = StakingInfo(freeStaking, freeStaking, 0, 0, 1);

        nodeID = start;
        for (uint256 i = 0; i < count; i++) {
            LockedStakingNode memory n = lockedStakingNodes[nodeID];
            ret[i + 1] = StakingInfo(n.initialStakeAmount, n.remainAmount, n.stakeTime, n.unlockInterval, n.division);
            nodeID = n.next;
        }

        return ret;
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

    function deposit(IERC20 tokenAddr, uint256 amount) external override skipTransferCallback {
        SafeERC20.safeTransferFrom(tokenAddr, _msgSender(), address(this), amount);
    }

    modifier onlyLockedStakingAdder() {
        require(_msgSender() == _lockedStakingAdder, "Staking: caller is not the locked staking adder");
        _;
    }

    modifier skipTransferCallback() {
        directCalling = ENTERED;
        _;
        directCalling = NOT_ENTERED;
    }
}
