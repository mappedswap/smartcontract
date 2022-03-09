pragma solidity =0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/swap/IRaijinSwapRouter.sol";
import "../interfaces/swap/IUniswapV2Factory.sol";
import "../interfaces/IWEUN.sol";
import "../libraries/swap/RaijinSwapLibrary.sol";
import "../libraries/TransferHelper.sol";

contract RaijinSwapRouter is OwnableUpgradeable, AccessControlUpgradeable, IRaijinSwapRouter {
    using SafeMath for uint256;

    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 private constant SELECTED_LP_ROLE = keccak256("SELECTED_LP_ROLE");
    bytes32 private constant SELECTED_SWAP_ROLE = keccak256("SELECTED_SWAP_ROLE");

    address public override factory;
    address public override WEUN;

    mapping(address => bool) private restrictedTokens;

    function initialize(address _factory, address _WEUN) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SELECTED_LP_ROLE, MANAGER_ROLE);

        factory = _factory;
        WEUN = _WEUN;
    }

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

    receive() external payable {
        assert(msg.sender == WEUN); // only accept EUN via fallback from the WEUN contract
    }

    function getManagers() external view override returns (address[] memory) {
        return getMembers(MANAGER_ROLE);
    }

    function getSelectedLiquidityProviders() external view override returns (address[] memory) {
        return getMembers(SELECTED_LP_ROLE);
    }

    function getSelectedSwappers() external view override returns (address[] memory) {
        return getMembers(SELECTED_SWAP_ROLE);
    }

    function grantManager(address addr) external override onlyOwner {
        grantRole(MANAGER_ROLE, addr);
    }

    function grantSelectedLiquidityProvider(address addr) external override onlyManager {
        grantRole(SELECTED_LP_ROLE, addr);
    }

    function grantSelectedSwapper(address addr) external override onlyManager {
        grantRole(SELECTED_SWAP_ROLE, addr);
    }

    function revokeManager(address addr) external override onlyOwner {
        revokeRole(MANAGER_ROLE, addr);
    }

    function revokeSelectedLiquidityProvider(address addr) external override onlyManager {
        revokeRole(SELECTED_LP_ROLE, addr);
    }

    function revokeSelectedSwapper(address addr) external override onlyManager {
        revokeRole(SELECTED_SWAP_ROLE, addr);
    }

    function isTokenRestricted(address token) external view override returns (bool) {
        return restrictedTokens[token];
    }

    function setTokenRestrictStatus(address token, bool restricted) external override onlyManager {
        restrictedTokens[token] = restricted;
    }

    function isLiquidityAllowed(
        address tokenA,
        address tokenB,
        address to
    ) public view override returns (bool) {
        // The latest version is only need the role when both tokens are restricted
        if (restrictedTokens[tokenA] == true && restrictedTokens[tokenB] == true) {
            return hasRole(SELECTED_LP_ROLE, to);
        }
        return true;
    }

    function isSwapAllowed(address[] memory path, address from) public view override returns (bool) {
        // Similiar to isLiquidityAllowed, if all tokens in path are restricted, require the special permission
        // And different from isLiquidityAllowed, here check the from address
        bool check = true;
        for (uint256 i = 0; i < path.length; i++) {
            if (restrictedTokens[path[i]] == false) {
                check = false;
                break;
            }
        }
        return check ? hasRole(SELECTED_SWAP_ROLE, from) : true;
    }

    function pairFor(address tokenA, address tokenB) external view override returns (address) {
        return RaijinSwapLibrary.pairFor(factory, tokenA, tokenB);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = RaijinSwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = RaijinSwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "RaijinSwapRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = RaijinSwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "RaijinSwapRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        // If either one token is restricted, only specific user can add liquidity
        // Also msg.sender and parameter to may not be the same address, so check parameter to who finally get liquidity token
        require(isLiquidityAllowed(tokenA, tokenB, to), "RaijinSwapRouter: RESTRICTED_TOKEN");

        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = RaijinSwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityEUN(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountEUNMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountEUN,
            uint256 liquidity
        )
    {
        // If either one token is restricted, only specific user can add liquidity
        // Also msg.sender and parameter to may not be the same address, so check parameter to who finally get liquidity token
        require(isLiquidityAllowed(token, WEUN, to), "RaijinSwapRouter: RESTRICTED_TOKEN");

        (amountToken, amountEUN) = _addLiquidity(token, WEUN, amountTokenDesired, msg.value, amountTokenMin, amountEUNMin);
        address pair = RaijinSwapLibrary.pairFor(factory, token, WEUN);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWEUN(WEUN).deposit{value: amountEUN}();
        assert(IWEUN(WEUN).transfer(pair, amountEUN));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eun, if any
        if (msg.value > amountEUN) TransferHelper.safeTransferEUN(msg.sender, msg.value - amountEUN);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        // Similar to add liquidity to restrict some tokens
        require(isLiquidityAllowed(tokenA, tokenB, to), "RaijinSwapRouter: RESTRICTED_TOKEN");

        address pair = RaijinSwapLibrary.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0, ) = RaijinSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "RaijinSwapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "RaijinSwapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityEUN(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountEUNMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountEUN) {
        (amountToken, amountEUN) = removeLiquidity(token, WEUN, liquidity, amountTokenMin, amountEUNMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IWEUN(WEUN).withdraw(amountEUN);
        TransferHelper.safeTransferEUN(to, amountEUN);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = RaijinSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityEUNWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountEUNMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountEUN) {
        address pair = RaijinSwapLibrary.pairFor(factory, token, WEUN);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountEUN) = removeLiquidityEUN(token, liquidity, amountTokenMin, amountEUNMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityEUNSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountEUNMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountEUN) {
        (, amountEUN) = removeLiquidity(token, WEUN, liquidity, amountTokenMin, amountEUNMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWEUN(WEUN).withdraw(amountEUN);
        TransferHelper.safeTransferEUN(to, amountEUN);
    }

    function removeLiquidityEUNWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountEUNMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountEUN) {
        address pair = RaijinSwapLibrary.pairFor(factory, token, WEUN);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountEUN = removeLiquidityEUNSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountEUNMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        require(isSwapAllowed(path, msg.sender), "RaijinSwapRouter: RESTRICTED_TOKEN");

        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = RaijinSwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? RaijinSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(RaijinSwapLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = RaijinSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = RaijinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "RaijinSwapRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactEUNForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        amounts = RaijinSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWEUN(WEUN).deposit{value: amounts[0]}();
        assert(IWEUN(WEUN).transfer(RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactEUN(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        amounts = RaijinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "RaijinSwapRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWEUN(WEUN).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferEUN(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForEUN(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        amounts = RaijinSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWEUN(WEUN).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferEUN(to, amounts[amounts.length - 1]);
    }

    function swapEUNForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        amounts = RaijinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "RaijinSwapRouter: EXCESSIVE_INPUT_AMOUNT");
        IWEUN(WEUN).deposit{value: amounts[0]}();
        assert(IWEUN(WEUN).transfer(RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eun, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferEUN(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        require(isSwapAllowed(path, msg.sender), "RaijinSwapRouter: RESTRICTED_TOKEN");

        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = RaijinSwapLibrary.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(RaijinSwapLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = RaijinSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? RaijinSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactEUNForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWEUN(WEUN).deposit{value: amountIn}();
        assert(IWEUN(WEUN).transfer(RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactTokensForEUNSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WEUN, "RaijinSwapRouter: INVALID_PATH");
        TransferHelper.safeTransferFrom(path[0], msg.sender, RaijinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WEUN).balanceOf(address(this));
        require(amountOut >= amountOutMin, "RaijinSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWEUN(WEUN).withdraw(amountOut);
        TransferHelper.safeTransferEUN(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return RaijinSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return RaijinSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return RaijinSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view virtual override returns (uint256[] memory amounts) {
        return RaijinSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view virtual override returns (uint256[] memory amounts) {
        return RaijinSwapLibrary.getAmountsIn(factory, amountOut, path);
    }

    function getMembers(bytes32 role) private view returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "RaijinSwapRouter: EXPIRED");
        _;
    }

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Manager only");
        _;
    }
}
