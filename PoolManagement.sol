pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol";
import "./interfaces/swap/IRaijinSwapRouter.sol";
import "./interfaces/swap/IUniswapV2Pair.sol";
import "./interfaces/IPoolApprover.sol";
import "./interfaces/IPoolCustomerUpdate.sol";
import "./interfaces/IPoolFunding.sol";
import "./interfaces/IPoolManager.sol";
import "./interfaces/IPoolOwner.sol";
import "./libraries/Constant.sol";
import "./libraries/Mode.sol";
import "./libraries/PoolStruct.sol";
import "./libraries/PoolUtilities.sol";
import "./libraries/String.sol";

contract PoolManagement is OwnableUpgradeable, AccessControlUpgradeable, ERC165Upgradeable, IPoolApprover, IPoolCustomerUpdate, IPoolFunding, IPoolManager, IPoolOwner {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using String for string;

    IRaijinSwapRouter private router;

    IERC20 private refToken;

    uint256 private interestInterval;

    mapping(address => PoolStruct.Customer) private customers;

    mapping(string => PoolStruct.Token) private tokens;
    string[] private tokenList;

    mapping(string => PoolStruct.Pair) private pairs;
    string[] private pairList;

    uint256 private reentrancyState;

    uint256 private directFundingToPool;

    uint256 private cumulativeLoss;

    uint256 private cumulativeCompensation;

    function owner() public view override(OwnableUpgradeable, IOwnable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    function renounceOwnership() public override(OwnableUpgradeable, IOwnable) {
        address _owner = owner();
        OwnableUpgradeable.renounceOwnership();
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function transferOwnership(address newOwner) public override(OwnableUpgradeable, IOwnable) {
        address _owner = owner();
        require(_owner != newOwner, "Ownable: self ownership transfer");

        OwnableUpgradeable.transferOwnership(newOwner);
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function updateCustomerDetails(
        address customer,
        int256 newMode,
        uint256 newLeverage,
        uint256 newFunding,
        int256 newRiskLevel,
        int256 newStatus
    ) external override onlyAgentOrManager {
        // Limit stopout risk level no larger than 100%
        require(newRiskLevel <= 1000000, "Risk level exceeds 100%");

        PoolStruct.Customer storage c = customers[customer];

        int256 oldMode = c.mode;
        uint256 oldLeverage = c.leverage;
        uint256 oldFunding = c.maxFunding;
        int256 oldRiskLevel = c.riskLevel;
        int256 oldStatus = c.status;

        // Only manager can set or unset address to dealer
        require(hasRole(Constant.MANAGER_ROLE, msg.sender) || newMode != Mode.DEALER_MODE, "Manager only");
        require(hasRole(Constant.MANAGER_ROLE, msg.sender) || oldMode != Mode.DEALER_MODE, "Manager only");

        if (oldMode != newMode) {
            c.mode = newMode;
            emit UpdateMode(customer, oldMode, newMode);
        }

        if (oldLeverage != newLeverage) {
            c.leverage = newLeverage;
            emit UpdateLeverage(customer, oldLeverage, newLeverage);
        }

        if (oldFunding != newFunding) {
            c.maxFunding = newFunding;
            emit UpdateFunding(customer, oldFunding, newFunding);
        }

        if (oldRiskLevel != newRiskLevel) {
            c.riskLevel = newRiskLevel;
            emit UpdateRiskLevel(customer, oldRiskLevel, newRiskLevel);
        }

        if (oldStatus != newStatus) {
            c.status = newStatus;
            emit UpdateStatus(customer, oldStatus, newStatus);
        }
    }

    function addPoolFunding(string calldata tokenName, uint256 amount) external override {
        PoolUtilities.tokenMustExist(tokenList, tokenName);

        // Similar to reentrancy guard
        directFundingToPool = Constant.ENTERED;
        SafeERC20.safeTransferFrom(tokens[tokenName].tokenAddr, msg.sender, address(this), amount);
        directFundingToPool = Constant.NOT_ENTERED;
    }

    function addPoolCompensation(uint256 amount) external override {
        // This function is basically same as addPoolFunding()
        // Except need to record cumulatve compensation, and only for refToken (USDM)
        cumulativeCompensation = cumulativeCompensation.add(amount);

        directFundingToPool = Constant.ENTERED;
        SafeERC20.safeTransferFrom(refToken, msg.sender, address(this), amount);
        directFundingToPool = Constant.NOT_ENTERED;
    }

    function getCumulativeLoss() external view override returns (uint256) {
        return cumulativeLoss;
    }

    function getCumulativeCompensation() external view override returns (uint256) {
        return cumulativeCompensation;
    }

    /* Token-related functions */

    function getTokenInfo(string calldata tokenName) external view override returns (PoolStruct.Token memory) {
        PoolStruct.Token storage t = tokens[tokenName];
        PoolStruct.InterestRate[] storage r = t.interestRates;
        PoolStruct.Token memory ret;
        ret.tokenAddr = t.tokenAddr;
        ret.interestRates = new PoolStruct.InterestRate[](1);
        ret.interestRates[0] = r[r.length - 1];
        ret.effectiveDecimal = t.effectiveDecimal;
        return ret;
    }

    function getTokenInterestHistory(string calldata tokenName, int256 limit) external view override returns (PoolStruct.InterestRate[] memory) {
        PoolStruct.InterestRate[] storage r = tokens[tokenName].interestRates;
        if (limit <= 0) {
            return r;
        }

        uint256 num = uint256(limit) >= r.length ? r.length : uint256(limit);
        PoolStruct.InterestRate[] memory ret = new PoolStruct.InterestRate[](num);
        uint256 pos = r.length - num;
        PoolUtilities.copyInterestRates(ret, r, pos, num);
        return ret;
    }

    function getAllTokens() external view override returns (string[] memory) {
        return tokenList;
    }

    function addToken(
        string calldata tokenName,
        IERC20 tokenAddr,
        uint256 interestRate
    ) external override onlyManager {
        require(!PoolUtilities.tokenExist(tokenList, tokenName), "Token already exists");

        tokenList.push(tokenName);

        PoolStruct.Token storage t = tokens[tokenName];
        t.tokenAddr = tokenAddr;

        // Suppose this value is too trivial, so not required to provide when adding token, but still give a function to change it if necessary
        t.effectiveDecimal = Constant.DEFAULT_EFFECTIVE_DECIMAL;

        // Reset interest rate history and add again
        // Interest rate is effective immediately
        delete t.interestRates;
        PoolStruct.InterestRate memory r = PoolStruct.InterestRate({value: interestRate, effectiveTime: PoolUtilities.nearestInterval(block.timestamp, interestInterval)});
        t.interestRates.push(r);

        // Will use Uniswap to swap tokens, so approve router contract as spender
        require(tokenAddr.approve(address(router), uint256(-1)));
    }

    function updateTokenInterestRate(string calldata tokenName, uint256 newInterestRate) external override onlyManager {
        PoolUtilities.tokenMustExist(tokenList, tokenName);

        // New interest rate will be effective from next interval
        PoolStruct.Token storage t = tokens[tokenName];
        uint256 l = t.interestRates.length;
        uint256 _interestInterval = interestInterval;
        uint256 time = PoolUtilities.nearestInterval(block.timestamp, _interestInterval).add(_interestInterval);

        uint256 oldInterestRate = t.interestRates[l - 1].value;
        uint256 oldEffectiveTime = t.interestRates[l - 1].effectiveTime;

        if (oldEffectiveTime == time) {
            // Change interest rate again in same interval, just update the value
            t.interestRates[l - 1].value = newInterestRate;
        } else {
            PoolStruct.InterestRate memory r = PoolStruct.InterestRate({value: newInterestRate, effectiveTime: time});
            t.interestRates.push(r);
        }

        emit UpdateTokenInterestRate(tokenName, oldInterestRate, oldEffectiveTime, newInterestRate, time);
    }

    function updateTokenEffectiveDecimal(string calldata tokenName, uint256 newEffectiveDecimal) external override onlyManager {
        PoolUtilities.tokenMustExist(tokenList, tokenName);

        PoolStruct.Token storage t = tokens[tokenName];

        uint256 oldEffectiveDecimal = t.effectiveDecimal;

        t.effectiveDecimal = newEffectiveDecimal;

        emit UpdateTokenEffectiveDecimal(tokenName, oldEffectiveDecimal, newEffectiveDecimal);
    }

    function removeToken(string calldata tokenName) external override onlyManager {
        int256 index = PoolUtilities.tokenIndex(tokenList, tokenName);
        require(index != -1, "Token not exist");

        tokenList[uint256(index)] = tokenList[tokenList.length - 1];
        tokenList.pop();
    }

    /* Pair-related functions */

    function getPairInfo(string calldata pairName) external view override returns (PoolStruct.PairInfo memory) {
        PoolStruct.Pair storage p = pairs[pairName];
        PoolStruct.PairInfo memory pi;
        pi.pairAddr = p.pairAddr;
        pi.token0Name = p.token0Name;
        pi.token1Name = p.token1Name;
        pi.token0Addr = p.token0Addr;
        pi.token1Addr = p.token1Addr;
        pi.enabled = p.enabled;

        // The address is calculated from create2, it may not actually exist
        if (Address.isContract(address(p.pairAddr))) {
            (pi.reserve0, pi.reserve1, pi.blockTimestampLast) = p.pairAddr.getReserves();
            pi.price0CumulativeLast = p.pairAddr.price0CumulativeLast();
            pi.price1CumulativeLast = p.pairAddr.price1CumulativeLast();
        }

        return pi;
    }

    function getAllPairs() external view override returns (string[] memory) {
        return pairList;
    }

    function addPair(string calldata tokenAName, string calldata tokenBName) external override onlyManager {
        PoolUtilities.tokenMustExist(tokenList, tokenAName);
        PoolUtilities.tokenMustExist(tokenList, tokenBName);

        string memory pairName = string(abi.encodePacked(tokenAName, "/", tokenBName));
        string memory reversePairName = string(abi.encodePacked(tokenBName, "/", tokenAName));
        require(!PoolUtilities.pairExist(pairList, pairName), "Pair already exists");

        pairList.push(pairName);
        pairList.push(reversePairName);

        IERC20 tokenA = tokens[tokenAName].tokenAddr;
        IERC20 tokenB = tokens[tokenBName].tokenAddr;
        (IERC20 token0, IERC20 token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        PoolStruct.Pair storage p = pairs[pairName];
        p.reversePairName = reversePairName;
        p.token0Name = token0 == tokenA ? tokenAName : tokenBName;
        p.token1Name = token0 == tokenA ? tokenBName : tokenAName;
        p.token0Addr = token0;
        p.token1Addr = token1;
        p.pairAddr = IUniswapV2Pair(router.pairFor(address(token0), address(token1)));
        p.enabled = true;

        // Also add to the reverse pair name
        PoolStruct.Pair storage rp = pairs[reversePairName];
        rp.reversePairName = pairName;
        rp.token0Name = p.token0Name;
        rp.token1Name = p.token1Name;
        rp.token0Addr = token0;
        rp.token1Addr = token1;
        rp.pairAddr = p.pairAddr;
        rp.enabled = true;
    }

    function updatePairEnableStatus(string calldata pairName, bool newEnableStatus) external override onlyManager {
        PoolUtilities.pairMustExist(pairList, pairName);

        PoolStruct.Pair storage p = pairs[pairName];

        bool oldEnableStatus = p.enabled;

        p.enabled = newEnableStatus;
        pairs[p.reversePairName].enabled = newEnableStatus;

        emit UpdatePairEnableStatus(pairName, oldEnableStatus, newEnableStatus);
    }

    function removePair(string calldata pairName) external override onlyManager {
        int256 index = PoolUtilities.pairIndex(pairList, pairName);
        require(index != -1, "Pair not exist");

        // Similar to token, bet remember also remove the reverse pair name
        string memory reversePairName = pairs[pairName].reversePairName;

        pairList[uint256(index)] = pairList[pairList.length - 1];
        pairList.pop();
        index = PoolUtilities.pairIndex(pairList, reversePairName);
        pairList[uint256(index)] = pairList[pairList.length - 1];
        pairList.pop();
    }

    /* Approver-related functions */

    function getAllowance(string calldata tokenName) external view override returns (uint256) {
        PoolStruct.Token storage t = tokens[tokenName];
        return t.tokenAddr.allowance(address(this), address(router));
    }

    function updateAllowance(string calldata tokenName, uint256 newAllowance) external override onlyApprover {
        PoolUtilities.tokenMustExist(tokenList, tokenName);

        require(tokens[tokenName].tokenAddr.approve(address(router), newAllowance));
    }

    /* Access control-related functions */

    function getAgents() external view override returns (address[] memory) {
        return getMembers(Constant.AGENT_ROLE);
    }

    function getApprovers() external view override returns (address[] memory) {
        return getMembers(Constant.APPROVER_ROLE);
    }

    function getBackends() external view override returns (address[] memory) {
        return getMembers(Constant.BACKEND_ROLE);
    }

    function getManagers() external view override returns (address[] memory) {
        return getMembers(Constant.MANAGER_ROLE);
    }

    function grantAgent(address agentAddr) external override onlyOwner {
        grantRole(Constant.AGENT_ROLE, agentAddr);
    }

    function grantApprover(address approverAddr) external override onlyOwner {
        grantRole(Constant.APPROVER_ROLE, approverAddr);
    }

    function grantBackend(address backendAddr) external override onlyOwner {
        grantRole(Constant.BACKEND_ROLE, backendAddr);
    }

    function grantManager(address managerAddr) external override onlyOwner {
        grantRole(Constant.MANAGER_ROLE, managerAddr);
    }

    function revokeAgent(address agentAddr) external override onlyOwner {
        revokeRole(Constant.AGENT_ROLE, agentAddr);
    }

    function revokeApprover(address approverAddr) external override onlyOwner {
        revokeRole(Constant.APPROVER_ROLE, approverAddr);
    }

    function revokeBackend(address backendAddr) external override onlyOwner {
        revokeRole(Constant.BACKEND_ROLE, backendAddr);
    }

    function revokeManager(address managerAddr) external override onlyOwner {
        revokeRole(Constant.MANAGER_ROLE, managerAddr);
    }

    /* Helper functions */

    function getMembers(bytes32 role) private view returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    modifier onlyAgentOrManager() {
        require(hasRole(Constant.AGENT_ROLE, msg.sender) || hasRole(Constant.MANAGER_ROLE, msg.sender), "Agent or manager only");
        _;
    }

    modifier onlyApprover() {
        require(hasRole(Constant.APPROVER_ROLE, msg.sender), "Approver only");
        _;
    }

    modifier onlyManager() {
        require(hasRole(Constant.MANAGER_ROLE, msg.sender), "Manager only");
        _;
    }
}
