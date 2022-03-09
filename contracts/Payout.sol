pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IPayout.sol";
import "./libraries/PayoutStruct.sol";
import "./libraries/QuickSort.sol";

contract Payout is OwnableUpgradeable, IPayout {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    uint256 private constant UNINITIALIZE = 0;
    uint256 private constant UPDATING = 1;
    uint256 private constant PENDING = 2;
    uint256 private constant VERIFIED = 3;
    uint256 private constant APPROVED = 4;
    uint256 private constant REVOKED = 5;

    uint256 private nextRoundID;

    mapping(uint256 => PayoutStruct.Round) private rounds;

    function initialize() public override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
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

    function getNextRoundID() external view override returns (uint256) {
        return nextRoundID;
    }

    function getRoundSummary(uint256 roundID) external view override returns (PayoutStruct.RoundSummary memory) {
        PayoutStruct.Round storage r = rounds[roundID];
        PayoutStruct.RoundSummary memory ret;

        ret.tokenList = new PayoutStruct.TokenPayoutSummany[](r.tokenList.length);
        for (uint256 i = 0; i < r.tokenList.length; i++) {
            address tokenAddr = r.tokenList[i];
            ret.tokenList[i].tokenAddr = tokenAddr;
            ret.tokenList[i].totalPayout = r.tokens[tokenAddr].totalPayout;
            ret.tokenList[i].claimedPayout = r.tokens[tokenAddr].claimedPayout;
        }

        ret.state = r.state;

        ret.creator = r.creator;
        ret.createTime = r.createTime;
        ret.finishTime = r.finishTime;

        ret.verifier = r.verifier;
        ret.verifyTime = r.verifyTime;

        ret.approver = r.approver;
        ret.approveTime = r.approveTime;

        return ret;
    }

    function verify(
        uint256 roundID,
        address agentAddr,
        address[] memory tokenList,
        uint256[] memory amountList
    ) public view override returns (bool) {
        uint256 length = tokenList.length;
        uint256[] memory orderArray = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            orderArray[i] = i;
        }

        QuickSort.sort(tokenList, orderArray);

        bytes memory data = abi.encodePacked(roundID, agentAddr);
        for (uint256 k = 0; k < length; k++) {
            uint256 amount = amountList[orderArray[k]];
            if (amount == 0) {
                continue;
            }

            data = abi.encodePacked(data, tokenList[k], amount);
        }

        return rounds[roundID].agentHashes[agentAddr] == keccak256(data);
    }

    function isClaimed(uint256 roundID, address agentAddr) external view override returns (bool) {
        return rounds[roundID].agentClaims[agentAddr];
    }

    function create() external override returns (uint256 roundID) {
        roundID = nextRoundID++;
        PayoutStruct.Round storage r = rounds[roundID];
        r.state = UPDATING;
        r.creator = msg.sender;
        r.createTime = block.timestamp;

        emit Created(roundID, msg.sender);
    }

    function update(
        uint256 roundID,
        address[] calldata tokenList,
        PayoutStruct.AgentPayoutInput[] calldata agentPayoutList
    ) external override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == UPDATING, "Not in creating state");
        require(r.creator == msg.sender, "Not the creator");

        uint256 length = tokenList.length;

        // tokenArray will be sorted
        // orderArray is used to find the original index of sorted items
        // payoutArray has the same order as input token addresses
        address[] memory tokenArray = new address[](length);
        uint256[] memory orderArray = new uint256[](length);
        uint256[] memory payoutArray = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            address tokenAddr = tokenList[i];
            PayoutStruct.TokenPayout storage tp = r.tokens[tokenAddr];

            tokenArray[i] = tokenAddr;
            orderArray[i] = i;
            payoutArray[i] = tp.totalPayout;

            // Need to maintain a list to save all tokens used in this round
            if (!tp.isAdded) {
                tp.isAdded = true;
                r.tokenList.push(tokenAddr);
            }
        }

        QuickSort.sort(tokenArray, orderArray);

        for (uint256 j = 0; j < agentPayoutList.length; j++) {
            address agentAddr = agentPayoutList[j].agentAddr;
            require(r.agentHashes[agentAddr] == 0, "Cannot edit");

            bytes memory data = abi.encodePacked(roundID, agentAddr);

            // Iterate the sorted array to create data for hash, skip any tokens with 0 amount
            for (uint256 k = 0; k < length; k++) {
                uint256 amount = agentPayoutList[j].amounts[orderArray[k]];
                if (amount == 0) {
                    continue;
                }

                payoutArray[orderArray[k]] = payoutArray[orderArray[k]].add(amount);
                data = abi.encodePacked(data, tokenArray[k], amount);
            }

            r.agentHashes[agentAddr] = keccak256(data);
        }

        // Write back total payout of each token
        for (uint256 i = 0; i < length; i++) {
            r.tokens[tokenList[i]].totalPayout = payoutArray[i];
        }
    }

    function updateFinish(uint256 roundID, address verifier) external override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == UPDATING, "Not in creating state");
        require(r.creator == msg.sender, "Not the creator");
        require(verifier != address(0), "Invalid verifier address");

        r.state = PENDING;
        r.finishTime = block.timestamp;
        r.verifier = verifier;

        emit UpdateFinished(roundID, msg.sender, verifier);
    }

    function verifyFinish(uint256 roundID) external override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == PENDING, "Not in pending state");
        require(r.verifier == msg.sender, "Not the verifier");

        r.state = VERIFIED;
        r.verifyTime = block.timestamp;

        emit Verified(roundID, msg.sender);
    }

    function approve(uint256 roundID, address verifier) external override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == VERIFIED, "Not in verified state");
        require(r.verifier == verifier, "Incorrect verifier");

        // Transfer tokens from sender to this contract, sender should approve in each ERC20 before calling this
        for (uint256 i = 0; i < r.tokenList.length; i++) {
            address tokenAddr = r.tokenList[i];
            require(IERC20(tokenAddr).transferFrom(msg.sender, address(this), r.tokens[tokenAddr].totalPayout));
        }

        r.state = APPROVED;
        r.approver = msg.sender;
        r.approveTime = block.timestamp;

        emit Approved(roundID, msg.sender);
    }

    function claim(
        uint256 roundID,
        address[] calldata tokenList,
        uint256[] calldata amountList
    ) external override {
        claimFor(roundID, msg.sender, tokenList, amountList);
    }

    function claimFor(
        uint256 roundID,
        address recipient,
        address[] memory tokenList,
        uint256[] memory amountList
    ) public override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == APPROVED, "Not in approved state");
        require(verify(roundID, recipient, tokenList, amountList), "Incorrect input");
        require(!r.agentClaims[recipient], "Already claimed");

        r.agentClaims[recipient] = true;

        for (uint256 i = 0; i < tokenList.length; i++) {
            uint256 amount = amountList[i];
            if (amount == 0) {
                continue;
            }

            address tokenAddr = tokenList[i];
            PayoutStruct.TokenPayout storage tp = r.tokens[tokenAddr];
            tp.claimedPayout = tp.claimedPayout.add(amount);
            require(IERC20(tokenAddr).transfer(recipient, amount));
        }

        emit Claimed(roundID, recipient, tokenList, amountList);
    }

    function revoke(uint256 roundID) external override {
        PayoutStruct.Round storage r = rounds[roundID];
        require(r.state == APPROVED, "Not in approved state");
        require(r.approver == msg.sender, "Not the approver");

        // Return remaining tokens to approver
        r.state = REVOKED;
        for (uint256 i = 0; i < r.tokenList.length; i++) {
            address tokenAddr = r.tokenList[i];
            PayoutStruct.TokenPayout storage tp = r.tokens[tokenAddr];
            require(IERC20(tokenAddr).transfer(msg.sender, tp.totalPayout.sub(tp.claimedPayout)));
        }

        emit Revoked(roundID, msg.sender);
    }
}
