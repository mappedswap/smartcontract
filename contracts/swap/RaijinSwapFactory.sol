pragma solidity =0.6.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/swap/IRaijinSwapFactory.sol";
import "../interfaces/swap/IRaijinSwapRouter.sol";
import "./RaijinSwapPair.sol";

contract RaijinSwapFactory is OwnableUpgradeable, IRaijinSwapFactory {
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    // For pair to know if recipient is allowed to add / remove liquidity
    address private router;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function initialize(address _feeToSetter) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();

        feeToSetter = _feeToSetter;
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

    function getRouter() external view override returns (address) {
        return router;
    }

    function setRouter(address _router) external override onlyOwner {
        // Because factory is deployed first then router, so this value need to be set afterwards
        router = _router;
    }

    function isLiquidityAllowed(
        address tokenA,
        address tokenB,
        address to
    ) external view override returns (bool) {
        // Just call router to do the real job
        return IRaijinSwapRouter(router).isLiquidityAllowed(tokenA, tokenB, to);
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "RaijinSwap: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "RaijinSwap: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "RaijinSwap: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(RaijinSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "RaijinSwap: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "RaijinSwap: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
