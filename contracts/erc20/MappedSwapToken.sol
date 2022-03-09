pragma solidity =0.6.6;

import "@openzeppelin/contracts/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/ERC223/IERC223Recipient.sol";
import "../interfaces/eurus/IEurusApprovalWallet.sol";
import "../interfaces/eurus/IEurusERC20.sol";
import "../interfaces/eurus/IEurusExternalSmartContractConfig.sol";
import "../interfaces/eurus/IEurusInternalSmartContractConfig.sol";
import "../interfaces/eurus/IEurusWalletAddressMap.sol";
import "../interfaces/IMappedSwapToken.sol";

contract MappedSwapToken is OwnableUpgradeable, AccessControlUpgradeable, ERC20Upgradeable, IMappedSwapToken, IEurusERC20 {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bytes4 private constant IERC223RecipientID = bytes4(keccak256("tokenReceived(address,uint256,bytes)"));

    // Used by EurusERC20 starts

    IEurusInternalSmartContractConfig internal internalSCConfig;

    IEurusExternalSmartContractConfig internal externalSCConfig;

    address[] public blackListDestAddress;

    mapping(address => bool) public blackListDestAddressMap;

    mapping(address => uint256) public dailyWithdrewAmount;

    // Used by EurusERC20 ends

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimal_
    ) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained(name_, symbol_);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupDecimals(decimal_);
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

    function name() public view override(ERC20Upgradeable, IERC223, IEurusERC20) returns (string memory) {
        return ERC20Upgradeable.name();
    }

    function symbol() public view override(ERC20Upgradeable, IERC223, IEurusERC20) returns (string memory) {
        return ERC20Upgradeable.symbol();
    }

    function standard() public view override returns (string memory) {
        return "erc223";
    }

    function decimals() public view override(ERC20Upgradeable, IERC223, IEurusERC20) returns (uint8) {
        return ERC20Upgradeable.decimals();
    }

    function totalSupply() public view override(ERC20Upgradeable, IMappedSwapToken, IERC20) returns (uint256) {
        return ERC20Upgradeable.totalSupply();
    }

    function balanceOf(address account) public view override(ERC20Upgradeable, IMappedSwapToken, IERC20) returns (uint256) {
        return ERC20Upgradeable.balanceOf(account);
    }

    function getMinters() external view override returns (address[] memory) {
        return getMembers(MINTER_ROLE);
    }

    function getBurners() external view override returns (address[] memory) {
        return getMembers(BURNER_ROLE);
    }

    function transfer(address recipient, uint256 amount) public override(ERC20Upgradeable, IMappedSwapToken, IERC20) returns (bool) {
        return transfer(recipient, amount, "");
    }

    function transfer(
        address recipient,
        uint256 amount,
        bytes memory data
    ) public override returns (bool) {
        require(ERC20Upgradeable.transfer(recipient, amount));

        if (Address.isContract(recipient) && ERC165Checker.supportsInterface(recipient, IERC223RecipientID)) {
            IERC223Recipient(recipient).tokenReceived(msg.sender, amount, data);
        }

        return true;
    }

    function allowance(address owner_, address spender) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return ERC20Upgradeable.allowance(owner_, spender);
    }

    function approve(address spender, uint256 amount) public override(ERC20Upgradeable, IERC20) returns (bool) {
        return ERC20Upgradeable.approve(spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20) returns (bool) {
        require(ERC20Upgradeable.transferFrom(sender, recipient, amount));

        if (Address.isContract(recipient) && ERC165Checker.supportsInterface(recipient, IERC223RecipientID)) {
            IERC223Recipient(recipient).tokenReceived(sender, amount, "");
        }

        return true;
    }

    function mint(address to, uint256 amount) external override(IMappedSwapToken, IEurusERC20) onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override(IMappedSwapToken, IEurusERC20) onlyBurner {
        _burn(from, amount);
    }

    function grantMinter(address minterAddr) external override onlyOwner {
        grantRole(MINTER_ROLE, minterAddr);
    }

    function grantBurner(address burnerAddr) external override onlyOwner {
        grantRole(BURNER_ROLE, burnerAddr);
    }

    function revokeMinter(address minterAddr) external override onlyOwner {
        revokeRole(MINTER_ROLE, minterAddr);
    }

    function revokeBurner(address burnerAddr) external override onlyOwner {
        revokeRole(BURNER_ROLE, burnerAddr);
    }

    function getMembers(bytes32 role) private view returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Minter only");
        _;
    }

    modifier onlyBurner() {
        require(hasRole(BURNER_ROLE, msg.sender), "Burner only");
        _;
    }

    // Used by EurusERC20, copy from original code, and just change data type to interface
    function submitWithdraw(
        address dest,
        uint256 withdrawAmount,
        uint256 amountWithFee
    ) external override onlyNonBlackListDestAddress(dest) {
        require(amountWithFee > withdrawAmount, "Total amount smaller than amount");
        uint256 feeAmount = amountWithFee - withdrawAmount;

        address walletMapAddr = internalSCConfig.getWalletAddressMap();
        require(walletMapAddr != address(0), "WalletAddressMap is null");
        IEurusWalletAddressMap walletAddrMap = IEurusWalletAddressMap(internalSCConfig.getWalletAddressMap());
        bool isExist = walletAddrMap.isWalletAddressExist(_msgSender());
        require(isExist, "Wallet is not registered");

        if ((int256(block.timestamp) / int256(86400)) * int256(86400) == (int256(walletAddrMap.getLastUpdateTime(_msgSender())) / int256(86400)) * int256(86400)) {
            require(externalSCConfig.getCurrencyKycLimit(symbol(), walletAddrMap.getWalletInfoValue(_msgSender(), "kycLevel")) >= dailyWithdrewAmount[_msgSender()] + withdrawAmount, "exceed daily withdraw amount");
            dailyWithdrewAmount[_msgSender()] = dailyWithdrewAmount[_msgSender()] + withdrawAmount;
        } else {
            require(externalSCConfig.getCurrencyKycLimit(symbol(), walletAddrMap.getWalletInfoValue(_msgSender(), "kycLevel")) >= withdrawAmount, "exceed daily withdraw amount");
            dailyWithdrewAmount[_msgSender()] = withdrawAmount;
        }
        walletAddrMap.setLastUpdateTime(_msgSender(), int256(block.timestamp));

        address adminFeeWalletAddr = internalSCConfig.getAdminFeeWalletAddress();
        bool adminFeeIsSuccess = transfer(adminFeeWalletAddr, feeAmount);
        require(adminFeeIsSuccess, "Transfer to AdminFee Wallet failed");

        address approvalWalletAddr = internalSCConfig.getApprovalWalletAddress();
        bool isSuccess = transfer(approvalWalletAddr, withdrawAmount);
        require(isSuccess, "Transfer to Approval Wallet failed");
        IEurusApprovalWallet approvalWallet = IEurusApprovalWallet(payable(approvalWalletAddr));
        approvalWallet.submitWithdrawRequest(_msgSender(), dest, withdrawAmount, symbol(), feeAmount);
    }

    function getInternalSCConfigAddress() external view override returns (address) {
        return address(internalSCConfig);
    }

    function setInternalSCConfigAddress(IEurusInternalSmartContractConfig addr) external override onlyOwner {
        internalSCConfig = addr;
    }

    function getExternalSCConfigAddress() external view override returns (address) {
        return address(externalSCConfig);
    }

    function setExternalSCConfigAddress(IEurusExternalSmartContractConfig addr) external override onlyOwner {
        externalSCConfig = addr;
    }

    function addBlackListDestAddress(address addr) external override onlyOwner onlyNonBlackListDestAddress(addr) {
        blackListDestAddressMap[addr] = true;
        blackListDestAddress.push(addr);
    }

    function removeBlackListDestAddress(address addr) external override onlyOwner onlyBlackListDestAddress(addr) {
        uint256 len = blackListDestAddress.length;
        for (uint256 i = 0; i < len; i++) {
            if (blackListDestAddress[i] == addr) {
                blackListDestAddress[i] = blackListDestAddress[len - 1];
                break;
            }
        }
        blackListDestAddress.pop();
        blackListDestAddressMap[addr] = false;
    }

    modifier onlyNonBlackListDestAddress(address destAddr) {
        require(!blackListDestAddressMap[destAddr], "Blacklist dest address");
        _;
    }

    modifier onlyBlackListDestAddress(address destAddr) {
        require(blackListDestAddressMap[destAddr], "Blacklist dest address not found");
        _;
    }
}
