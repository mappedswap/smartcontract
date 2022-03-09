pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/swap/IUniswapV2Factory.sol";
import "./interfaces/swap/IUniswapV2Pair.sol";
import "./interfaces/swap/IUniswapV2Router02.sol";
import "./interfaces/IPoolCustomer.sol";
import "./interfaces/IPriceAdjust.sol";
import "./libraries/Math.sol";
import "./libraries/String.sol";

contract PriceAdjust is OwnableUpgradeable, AccessControlUpgradeable, IPriceAdjust {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using String for string;

    bytes32 private constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    string private constant REF_TOKEN_NAME = "USDM";

    IPoolCustomer private pool;

    struct Variables {
        // Struct to avoid stack too deep
        int256 expN;
        int256 expD;
        string tokenNameSell;
        int256 a;
        int256 b;
        int256 c;
        int256 discriminant;
        int256 root1;
        int256 root2;
    }

    function initialize(IPoolCustomer _pool) public override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        pool = _pool;
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

    function getPool() external view override returns (address) {
        return address(pool);
    }

    function setPool(IPoolCustomer poolAddr) external override onlyManager {
        pool = poolAddr;
    }

    function adjust(
        string calldata tokenName,
        ERC20 tokenAddr,
        int256 targetPrice,
        uint8 decimals
    ) external override onlyBackend {
        ERC20 refToken = ERC20(pool.getReferenceToken());
        IUniswapV2Pair pair = IUniswapV2Pair(IUniswapV2Factory(IUniswapV2Router02(pool.getRouter()).factory()).getPair(address(refToken), address(tokenAddr)));

        Variables memory v;
        if ((uint256(decimals).add(uint256(tokenAddr.decimals()))) >= uint256(refToken.decimals())) {
            v.expN = int256(10**(uint256(decimals).add(uint256(tokenAddr.decimals())).sub(uint256(refToken.decimals()))));
            v.expD = 1;
        } else {
            v.expN = 1;
            v.expD = int256(10**(uint256(refToken.decimals()).sub(uint256(decimals)).sub(uint256(tokenAddr.decimals()))));
        }

        int256 reserveR;
        int256 reserveT;
        {
            // Scope to avoid stack too deep
            (uint256 r0, uint256 r1, ) = pair.getReserves();
            reserveR = pair.token0() == address(refToken) ? int256(r0) : int256(r1);
            reserveT = pair.token0() == address(refToken) ? int256(r1) : int256(r0);
        }

        int256 currentPrice = reserveR.mul(v.expN).div(reserveT.mul(v.expD));

        // If current price is lower than target, sell reference token to rise the price
        // Similarly if current price is higher than target, sell token to drop the price
        // Amount to sell can be found by solving the quadratic equation
        // If both a, b, c are multipled by the denominator in c, this can reduce error due to division
        // However numbers become very big and easy to overflow when calculating discriminant
        // So sacrifice some accuracy to make calculation succeed in more situations
        if (currentPrice < targetPrice) {
            v.tokenNameSell = REF_TOKEN_NAME;
            v.a = 997;
            v.b = reserveR.mul(1997);
            v.c = reserveR.mul(1000).mul(v.expN.mul(reserveR).sub(v.expD.mul(targetPrice).mul(reserveT))).div(v.expN);
        } else if (currentPrice > targetPrice) {
            v.tokenNameSell = tokenName;
            v.a = 997;
            v.b = reserveT.mul(1997);
            v.c = reserveT.mul(1000).mul(v.expD.mul(targetPrice).mul(reserveT).sub(v.expN.mul(reserveR))).div(v.expD.mul(targetPrice));
        } else {
            // No price change
            return;
        }

        v.discriminant = v.b.mul(v.b).sub(v.a.mul(v.c).mul(4));
        require(v.discriminant >= 0, "Cannot find real root of amount to sell");

        v.root1 = v.b.mul(-1).add(int256(Math.sqrt(uint256(v.discriminant)))).div(v.a.mul(2));
        v.root2 = v.b.mul(-1).sub(int256(Math.sqrt(uint256(v.discriminant)))).div(v.a.mul(2));

        // Only 1 root is suitable to use, it should be the smaller one which >= 0
        int256 root;
        if (v.root1 >= 0 && v.root2 >= 0) {
            root = v.root1 <= v.root2 ? v.root1 : v.root2;
        } else if (v.root1 >= 0) {
            root = v.root1;
        } else if (v.root2 >= 0) {
            root = v.root2;
        } else {
            revert("No non negative solution");
        }

        if (root == 0) {
            // Current price may be very close to target so the root is 0, in this case no need to do anything
            return;
        }

        if (IUniswapV2Router02(pool.getRouter()).getAmountOut(uint256(root), uint256(v.tokenNameSell.equals(REF_TOKEN_NAME) ? reserveR : reserveT), uint256(v.tokenNameSell.equals(REF_TOKEN_NAME) ? reserveT : reserveR)) == 0) {
            // Sell amount is so small so that buy amount becomes 0, also just skip this case
            return;
        }

        pool.sell(address(this), string(abi.encodePacked(tokenName, "/", REF_TOKEN_NAME)), v.tokenNameSell, uint256(root), 0, block.timestamp + 600);
    }

    function topUp(ERC20 tokenAddr, uint256 amount) external override onlyBackend {
        require(tokenAddr.transfer(address(pool), amount));
    }

    function withdraw(string calldata tokenName, uint256 amount) external override onlyBackend {
        pool.withdraw(tokenName, amount);
    }

    function getBackends() external view override returns (address[] memory) {
        return getMembers(BACKEND_ROLE);
    }

    function getManagers() external view override returns (address[] memory) {
        return getMembers(MANAGER_ROLE);
    }

    function grantBackend(address backendAddr) external override onlyOwner {
        grantRole(BACKEND_ROLE, backendAddr);
    }

    function grantManager(address managerAddr) external override onlyOwner {
        grantRole(MANAGER_ROLE, managerAddr);
    }

    function revokeBackend(address backendAddr) external override onlyOwner {
        revokeRole(BACKEND_ROLE, backendAddr);
    }

    function revokeManager(address managerAddr) external override onlyOwner {
        revokeRole(MANAGER_ROLE, managerAddr);
    }

    function getMembers(bytes32 role) private view returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    modifier onlyBackend() {
        require(hasRole(BACKEND_ROLE, msg.sender), "Backend only");
        _;
    }

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Manager only");
        _;
    }
}
