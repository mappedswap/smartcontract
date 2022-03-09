pragma solidity =0.6.6;

import "./interfaces/IWEUN.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract WrappedEUN is IWEUN {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function name() external view override returns (string memory) {
        return "Wrapped EUN";
    }

    function symbol() external view override returns (string memory) {
        return "WEUN";
    }

    function decimals() external view override returns (uint8) {
        return 18;
    }

    function totalSupply() external view override returns (uint256) {
        return payable(address(this)).balance;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    receive() external payable {
        _balances[msg.sender] = _balances[msg.sender].add(msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function deposit() external payable override {
        _balances[msg.sender] = _balances[msg.sender].add(msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function depositTo(address recipient) external payable override {
        if (recipient == address(0)) {
            // Treat deposit EUN to 0 = wrap and give it to myself
            _balances[msg.sender] = _balances[msg.sender].add(msg.value);
            emit Transfer(address(0), msg.sender, msg.value);
        } else {
            _balances[recipient] = _balances[recipient].add(msg.value);
            emit Transfer(address(0), recipient, msg.value);
        }
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        if (recipient == address(0)) {
            // Transfer token to 0 => burn token => withdraw
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
            emit Transfer(msg.sender, address(0), amount);
        } else {
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(msg.sender, recipient, amount);
        }

        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (sender != msg.sender) {
            uint256 allowed = _allowances[sender][msg.sender];

            // Update allowance if it is not set to no limit
            if (allowed != uint256(-1)) {
                uint256 newAllowed = allowed.sub(amount);
                _allowances[sender][msg.sender] = newAllowed;
                emit Approval(sender, msg.sender, newAllowed);
            }
        }

        _balances[sender] = _balances[sender].sub(amount);

        if (recipient == address(0)) {
            // Transfer token of sender to 0 => burn token => withdraw to msg.sender
            // This is same as WETH10
            // If sender is msg.sender itself the action should behave same as transfer(address,uint256)
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
            emit Transfer(sender, address(0), amount);
        } else {
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(sender, recipient, amount);
        }

        return true;
    }

    function withdraw(uint256 amount) external override {
        // Burn token and return EUN to me
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit Transfer(msg.sender, address(0), amount);
    }

    function withdrawTo(address payable recipient, uint256 amount) external override {
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        if (recipient == address(0)) {
            // Withdraw to 0 => burn token => return EUN to me, same as withdraw(uint256)
            // This is not handled in WETH10, add this to prevent EUN lost permanently
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            // Withdraw to other address => burn token and give EUN to someone
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Transfer failed");
        }

        emit Transfer(msg.sender, address(0), amount);
    }

    function withdrawFrom(
        address sender,
        address payable recipient,
        uint256 amount
    ) external override {
        if (sender != msg.sender) {
            uint256 allowed = _allowances[sender][msg.sender];

            // Update allowance if it is not set to no limit
            if (allowed != uint256(-1)) {
                uint256 newAllowed = allowed.sub(amount);
                _allowances[sender][msg.sender] = newAllowed;
                emit Approval(sender, msg.sender, newAllowed);
            }
        }

        _balances[sender] = _balances[sender].sub(amount);

        if (recipient == address(0)) {
            // Withdraw token of sender to 0 => burn token => withdraw to msg.sender
            // If sender is msg.sender itself the action should behave same as withdraw(uint256)
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            // Withdraw to other address => burn token and give EUN to someone
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Transfer failed");
        }

        emit Transfer(sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}
