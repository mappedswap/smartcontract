pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol";
import "./interfaces/ERC223/IERC223Recipient.sol";
import "./interfaces/swap/IRaijinSwapRouter.sol";
import "./interfaces/IPoolCustomerInfo.sol";
import "./interfaces/IPoolInternal.sol";
import "./interfaces/IPoolStopout.sol";
import "./interfaces/IPoolTrading.sol";
import "./libraries/Constant.sol";
import "./libraries/CustomerStatus.sol";
import "./libraries/Mode.sol";
import "./libraries/PoolStruct.sol";
import "./libraries/PoolUtilities.sol";
import "./libraries/String.sol";

contract PoolCore is OwnableUpgradeable, AccessControlUpgradeable, ERC165Upgradeable, IERC165, IERC223Recipient, IPoolCustomerInfo, IPoolInternal, IPoolStopout, IPoolTrading {
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

    function initialize(
        IRaijinSwapRouter _router,
        IERC20 _refToken,
        uint256 _interestInterval
    ) public override initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __AccessControl_init_unchained();
        __ERC165_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(Constant.DEPLOYER_ROLE, msg.sender);

        router = _router;
        refToken = _refToken;
        interestInterval = _interestInterval;

        IERC223Recipient i;
        _registerInterface(i.tokenReceived.selector);
    }

    function owner() public view override returns (address) {
        return OwnableUpgradeable.owner();
    }

    function renounceOwnership() public override {
        address _owner = owner();
        OwnableUpgradeable.renounceOwnership();
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function transferOwnership(address newOwner) public override {
        address _owner = owner();
        require(_owner != newOwner, "Ownable: self ownership transfer");

        OwnableUpgradeable.transferOwnership(newOwner);
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function getRouter() external view override returns (address) {
        return address(router);
    }

    function getReferenceToken() external view override returns (address) {
        return address(refToken);
    }

    function getCustomerInfo(address customer) external view override returns (PoolStruct.CustomerInfo memory) {
        PoolStruct.Customer storage c = customers[customer];
        PoolStruct.CustomerInfo memory ci;

        int256 equity = 0;
        uint256 usedFunding = 0;
        uint256 endInterval = PoolUtilities.nearestInterval(block.timestamp, interestInterval);

        bool exlcudeInterest = excludeFromInterestCalculation(customer);

        ci.tokens = new PoolStruct.CustomerTokenInfo[](tokenList.length);
        for (uint256 i = 0; i < tokenList.length; i++) {
            string memory tokenName = tokenList[i];
            PoolStruct.Token storage t = tokens[tokenName];
            int256 balance = c.balances[tokenName];

            ci.tokens[i].tokenName = tokenName;
            ci.tokens[i].realizedBalance = balance;

            if (exlcudeInterest) {
                ci.tokens[i].interest = 0;
                ci.tokens[i].interestRates = new PoolStruct.InterestRate[](0);
            } else {
                uint256 start;
                uint256 num;
                (ci.tokens[i].interest, start, num) = calculateInterest(c.mode, tokenName, balance, c.lastInterestCalcTime, endInterval);
                ci.tokens[i].interestRates = new PoolStruct.InterestRate[](num);
                PoolUtilities.copyInterestRates(ci.tokens[i].interestRates, t.interestRates, start, num);
            }

            int256 refTokenEquiv = getReferenceTokenEquivalent(address(t.tokenAddr), balance.sub(int256(ci.tokens[i].interest)));
            if (refTokenEquiv < 0) {
                usedFunding = usedFunding.add(uint256(-refTokenEquiv));
            }

            ci.tokens[i].usdmEquivalent = refTokenEquiv;
            equity = equity.add(refTokenEquiv);
        }

        ci.equity = equity;
        ci.mode = c.mode;
        ci.leverage = c.leverage;
        ci.maxFunding = c.maxFunding;
        ci.usedFunding = usedFunding;
        ci.stopoutRiskLevel = c.riskLevel;
        ci.currentRiskLevel = calculateRiskLevel(customer, usedFunding, equity);
        ci.lastInterestCalcTime = c.lastInterestCalcTime;
        ci.interestCalcCutoffTime = endInterval;
        ci.status = c.status;
        return ci;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable, IERC165) returns (bool) {
        return ERC165Upgradeable.supportsInterface(interfaceId);
    }

    function tokenReceived(
        address from,
        uint256 amount,
        bytes memory data
    ) public override nonReentrant {
        // Add funding to pool directly, no add to customer balance, just return
        if (directFundingToPool == Constant.ENTERED) {
            return;
        }

        // Uniswap pair may transfer token to this contract, so need to exclude them
        for (uint256 i = 0; i < pairList.length; i++) {
            if (address(pairs[pairList[i]].pairAddr) == from) {
                return;
            }
        }

        // User can deposit for other customer, in this case, customer address should be included in data
        // It should be exactly 32 bytes data, left-padded address value
        address customer;
        if (data.length > 0) {
            require(data.length == 32, "incorrect data format");
            assembly {
                customer := mload(add(data, 32))
            }
        } else {
            customer = from;
        }

        customerNotDisabled(customer);

        PoolStruct.Customer storage c = customers[customer];

        // Only added token can call this function
        for (uint256 i = 0; i < tokenList.length; i++) {
            string memory tokenName = tokenList[i];
            if (address(tokens[tokenName].tokenAddr) != msg.sender) {
                continue;
            }

            settleInterest(customer);

            int256 newBalance = c.balances[tokenName].add(int256(amount));
            c.balances[tokenName] = newBalance;

            emit IncreaseBalance(customer, tokenName, amount, newBalance);
            return;
        }

        revert("Token not exist");
    }

    function withdraw(string calldata tokenName, uint256 amount) external override {
        withdrawTo(msg.sender, tokenName, amount);
    }

    function withdrawTo(
        address toCustomer,
        string memory tokenName,
        uint256 amount
    ) public override nonReentrant onlyCustomerThemself(toCustomer) {
        // Currently disable withdraw by other address, so this function is equivalent to withdraw()
        customerNotDisabled(toCustomer);
        PoolUtilities.tokenMustExist(tokenList, tokenName);

        PoolStruct.Customer storage c = customers[toCustomer];

        // Ensure not using any funding
        settleInterest(toCustomer);
        (uint256 usedFunding, ) = getUsedFundingAndEquity(toCustomer);
        require(usedFunding == 0, "Return all funding first");

        // Cannot withdraw more than customer has
        int256 oldBalance = c.balances[tokenName];
        require(uint256(oldBalance) >= amount, "Insufficient amount");

        int256 newBalance = oldBalance.sub(int256(amount));
        c.balances[tokenName] = newBalance;
        SafeERC20.safeTransfer(tokens[tokenName].tokenAddr, toCustomer, amount);

        emit Withdraw(toCustomer, tokenName, amount, newBalance);
    }

    function buy(
        address customer,
        string calldata pairName,
        string calldata tokenNameBuy,
        uint256 amountBuy,
        uint256 amountSellMax,
        uint256 deadline
    ) external override onlyCustomerThemself(customer) {
        customerNotDisabled(customer);

        // Pair may not exist or enabled for trading, so do the checking first
        string memory tokenNameSell = checkPairAndGetOtherTokenName(pairName, tokenNameBuy);

        settleInterest(customer);

        uint256 beforeTotalFunding = getTotalFunding(customer);
        uint256 amountSell;
        {
            (address tokenAddrBuy, address tokenAddrSell) = (address(tokens[tokenNameBuy].tokenAddr), address(tokens[tokenNameSell].tokenAddr));
            amountSell = _buy(tokenAddrBuy, tokenAddrSell, amountBuy, amountSellMax, deadline);
        }
        (int256 newBalanceSell, int256 newBalanceBuy) = afterSwapProcess(customer, tokenNameSell, amountSell, tokenNameBuy, amountBuy, true, beforeTotalFunding);

        emit Buy(customer, pairName, tokenNameBuy, amountBuy, newBalanceBuy, amountSell, newBalanceSell, false);

        lossChecking(customer);
    }

    function sell(
        address customer,
        string calldata pairName,
        string calldata tokenNameSell,
        uint256 amountSell,
        uint256 amountBuyMin,
        uint256 deadline
    ) external override onlyCustomerThemself(customer) {
        customerNotDisabled(customer);

        // Pair may not exist or enabled for trading, so do the checking first
        string memory tokenNameBuy = checkPairAndGetOtherTokenName(pairName, tokenNameSell);

        settleInterest(customer);

        uint256 beforeTotalFunding = getTotalFunding(customer);
        uint256 amountBuy;
        {
            (address tokenAddrSell, address tokenAddrBuy) = (address(tokens[tokenNameSell].tokenAddr), address(tokens[tokenNameBuy].tokenAddr));
            amountBuy = _sell(tokenAddrSell, tokenAddrBuy, amountSell, amountBuyMin, deadline);
        }
        (int256 newBalanceSell, int256 newBalanceBuy) = afterSwapProcess(customer, tokenNameSell, amountSell, tokenNameBuy, amountBuy, true, beforeTotalFunding);

        emit Sell(customer, pairName, tokenNameSell, amountSell, newBalanceSell, amountBuy, newBalanceBuy, false);

        lossChecking(customer);
    }

    function stopout(address customer) external override onlyBackend {
        PoolStruct.Customer storage c = customers[customer];

        require(c.mode != Mode.DEALER_MODE, "Cannot stopout dealer");

        settleInterest(customer);

        (uint256 usedFunding, int256 equity) = getUsedFundingAndEquity(customer);

        bool hasTrade = false;

        address _refToken = address(refToken);

        // Loop all tokens, buy or sell any tokens other than USDM
        for (uint256 i = 0; i < tokenList.length; i++) {
            string memory tokenName = tokenList[i];

            if (address(tokens[tokenName].tokenAddr) == _refToken) {
                continue;
            }

            int256 balance = c.balances[tokenName];
            int256 displayBalance = balanceForDisplay(tokenName, balance);
            address tokenAddr = address(tokens[tokenName].tokenAddr);
            uint256 amountSell;
            uint256 amountBuy;
            int256 newBalanceSell;
            int256 newBalanceBuy;

            // Here use displayBalance for checking
            // Because customer may "manually" stopout by trade
            // In this case actual balance could be a very small amount, which can be omitted
            if (displayBalance == 0) {
                continue;
            } else if (displayBalance > 0) {
                hasTrade = true;
                amountSell = uint256(balance);
                amountBuy = _sell(tokenAddr, _refToken, amountSell, 0, block.timestamp.add(600));
                (newBalanceSell, newBalanceBuy) = afterSwapProcess(customer, tokenName, amountSell, Constant.REF_TOKEN_NAME, amountBuy, false, 0);
                emit Sell(customer, string(abi.encodePacked(tokenName, "/", Constant.REF_TOKEN_NAME)), tokenName, amountSell, newBalanceSell, amountBuy, newBalanceBuy, true);
            } else {
                hasTrade = true;
                amountBuy = uint256(-balance);
                amountSell = _buy(tokenAddr, _refToken, amountBuy, uint256(-1), block.timestamp.add(600));
                (newBalanceSell, newBalanceBuy) = afterSwapProcess(customer, Constant.REF_TOKEN_NAME, amountSell, tokenName, amountBuy, false, 0);
                emit Buy(customer, string(abi.encodePacked(tokenName, "/", Constant.REF_TOKEN_NAME)), tokenName, amountBuy, newBalanceBuy, amountSell, newBalanceSell, true);
            }
        }

        if (hasTrade) {
            // All other tokens are swapped to USDM, so the lastest USDM balance is also the total balance of customer
            emit Stopout(customer, equity, usedFunding, c.balances[Constant.REF_TOKEN_NAME]);

            // After stopout, if balance of reference token is still negative
            // Customer will probably ignore it and won't return the loan
            // Then this becomes loss
            lossChecking(customer);
        }
    }

    function _buy(
        address tokenAddrBuy,
        address tokenAddrSell,
        uint256 amountBuy,
        uint256 amountSellMax,
        uint256 deadline
    ) private returns (uint256) {
        address[] memory path = new address[](2);
        (path[0], path[1]) = (tokenAddrSell, tokenAddrBuy);
        uint256[] memory amounts = router.swapTokensForExactTokens(amountBuy, amountSellMax, path, address(this), deadline);
        return amounts[0];
    }

    function _sell(
        address tokenAddrSell,
        address tokenAddrBuy,
        uint256 amountSell,
        uint256 amountBuyMin,
        uint256 deadline
    ) private returns (uint256) {
        address[] memory path = new address[](2);
        (path[0], path[1]) = (tokenAddrSell, tokenAddrBuy);
        uint256[] memory amounts = router.swapExactTokensForTokens(amountSell, amountBuyMin, path, address(this), deadline);
        return amounts[amounts.length - 1];
    }

    function settleInterest(address customer) private {
        // Use address but not PoolStruct.Customer as parameter, as this function may need the address for event emit
        PoolStruct.Customer storage c = customers[customer];
        uint256 start = c.lastInterestCalcTime;
        uint256 end = PoolUtilities.nearestInterval(block.timestamp, interestInterval);

        // Must be 0 interest, can skip calculation, also no event is emitted
        if (start == end) {
            return;
        }

        bool exlcudeInterest = excludeFromInterestCalculation(customer);
        if (!exlcudeInterest) {
            uint256 len = tokenList.length;
            string[] memory tokenNames = new string[](len);
            int256[] memory realizedBalances = new int256[](len);
            uint256[] memory interests = new uint256[](len);

            for (uint256 i = 0; i < len; i++) {
                string memory tokenName = tokenList[i];
                tokenNames[i] = tokenName;
                int256 balance = c.balances[tokenName];
                realizedBalances[i] = balance;
                (uint256 interest, , ) = calculateInterest(c.mode, tokenName, balance, start, end);
                interests[i] = interest;
                if (interest > 0) {
                    c.balances[tokenName] = balance.sub(int256(interest));
                }
            }

            emit Interest(customer, start, end, tokenNames, realizedBalances, interests);
        }

        c.lastInterestCalcTime = end;
    }

    function afterSwapProcess(
        address customer,
        string memory tokenNameSell,
        uint256 amountSell,
        string memory tokenNameBuy,
        uint256 amountBuy,
        bool doValidation,
        uint256 beforeTotalFunding
    ) private returns (int256 newBalanceSell, int256 newBalanceBuy) {
        PoolStruct.Customer storage c = customers[customer];

        int256 oldBalanceSell = c.balances[tokenNameSell];
        newBalanceSell = oldBalanceSell.sub(int256(amountSell));
        c.balances[tokenNameSell] = newBalanceSell;

        int256 oldBalanceBuy = c.balances[tokenNameBuy];
        newBalanceBuy = oldBalanceBuy.add(int256(amountBuy));
        c.balances[tokenNameBuy] = newBalanceBuy;

        if (doValidation) {
            // Reducing position is always allowed regardless of funding
            if (tokenNameSell.equals(Constant.REF_TOKEN_NAME)) {
                // Reduce position by buying token, that means originally balance is negative, and buy to make balance towards 0
                // Because balance for display is always round-down of actual value
                // For example if user balance was -1.12345601, it will be displayed as -1.123457
                // To close the position user buys 1.123457, actual balance becomes 0.00000099
                // In this case display balance is 0.000000, so allow to do this trade
                if (oldBalanceBuy < 0 && balanceForDisplay(tokenNameBuy, newBalanceBuy) <= 0) {
                    return (newBalanceSell, newBalanceBuy);
                }
            } else if (tokenNameBuy.equals(Constant.REF_TOKEN_NAME)) {
                // Reduce position by selling token
                // That means originally balance is positive, and sell to make balance towards 0
                if (oldBalanceSell > 0 && newBalanceSell >= 0) {
                    return (newBalanceSell, newBalanceBuy);
                }
            } else {
                // This case should not be reached normally, currently either 1 token must be USDM
                revert("Pair not allowed");
            }

            (uint256 afterUsedFunding, int256 equity) = getUsedFundingAndEquity(customer);

            // Special and the only requirement for uninitialized user, no funding can be used
            if (c.status == CustomerStatus.UNINITIALIZE) {
                require(afterUsedFunding == 0, "No funding can be used");
                return (newBalanceSell, newBalanceBuy);
            }

            // Used funding does not exceed total, no problem
            if (afterUsedFunding <= beforeTotalFunding) {
                return (newBalanceSell, newBalanceBuy);
            }

            // Exceeded total funding, in the past this is not allowed
            // But now change to allow user switch position, as long as no new borrowing is made
            // However risk level is still a must-check
            require(calculateRiskLevel(customer, afterUsedFunding, equity) <= c.riskLevel, "Above risk level limit");
            require(oldBalanceSell > 0 && newBalanceSell >= 0, "Cannot borrow anymore");
        }
    }

    function getUsedFundingAndEquity(address customer) private view returns (uint256 usedFunding, int256 equity) {
        PoolStruct.Customer storage c = customers[customer];

        // To reduce calculation, this function should be called after interests are settled in this interval
        // So that USDM equivalant can be directly come from token balance
        require(PoolUtilities.nearestInterval(block.timestamp, interestInterval) == c.lastInterestCalcTime);

        usedFunding = 0;
        equity = 0;

        for (uint256 i = 0; i < tokenList.length; i++) {
            string memory tokenName = tokenList[i];
            int256 refTokenEquiv = getReferenceTokenEquivalent(address(tokens[tokenName].tokenAddr), c.balances[tokenName]);
            if (refTokenEquiv < 0) {
                usedFunding = usedFunding.add(uint256(-refTokenEquiv));
            }
            equity = equity.add(refTokenEquiv);
        }
    }

    function getTotalFunding(address customer) private view returns (uint256) {
        PoolStruct.Customer storage c = customers[customer];

        if (c.status == CustomerStatus.UNINITIALIZE) {
            return 0;
        }

        // Total funding is calculated by equity multiply leverage, and capped by maxFunding
        // For example if user deposit 10K USDM with 10X leverage, then total funding will be 100K (USDM equivalent)
        // But note that if user uses all 100K funding to short a token, because the swap requires transaction fee
        // Equity after swap will less than 10K, making the new total funding also less than 100K
        if (c.mode == Mode.MARGIN_MODE) {
            (, int256 equity) = getUsedFundingAndEquity(customer);

            // No equity, no funding, caller should decide what to do in this case
            if (equity <= 0) {
                return 0;
            }

            // Leverage has decimal place of 3
            uint256 value = uint256(equity).mul(c.leverage).div(1000);
            return c.maxFunding <= value ? c.maxFunding : value;
        } else {
            return c.maxFunding;
        }
    }

    function lossChecking(address customer) private {
        // Loss is defined as reference token has negative balance, while others are 0
        // In this situation, interest calculation is excluded
        // So use this to determine if loss is occurred
        bool exlcudeInterest = excludeFromInterestCalculation(customer);
        if (!exlcudeInterest) {
            return;
        }

        PoolStruct.Customer storage c = customers[customer];
        int256 balance = c.balances[Constant.REF_TOKEN_NAME];

        // That means interest calculation is excluded just because all tokens have non negative balance
        // No loss in this case
        if (balance >= 0) {
            return;
        }

        uint256 _cumulativeLoss = cumulativeLoss.add(uint256(-balance));
        cumulativeLoss = _cumulativeLoss;
        emit Loss(customer, uint256(-balance), _cumulativeLoss);
    }

    function excludeFromInterestCalculation(address customer) private view returns (bool) {
        // If all tokens have non-negative balance, then obviously no need to do interest calculation
        // Another case is balance of reference token is negative, but any other tokens have 0 balance
        // We decided not to calculate in this case, because this may be happened after stopout
        PoolStruct.Customer storage c = customers[customer];

        bool refTokenNegative = false;
        bool otherTokensZero = true;

        for (uint256 i = 0; i < tokenList.length; i++) {
            string memory tokenName = tokenList[i];
            int256 balance = c.balances[tokenName];

            if (tokenName.equals(Constant.REF_TOKEN_NAME)) {
                refTokenNegative = balance < 0;
            } else {
                int256 b = balanceForDisplay(tokenName, balance);

                // Obviously need the calculation
                if (b < 0) {
                    return false;
                }

                if (b != 0) {
                    otherTokensZero = false;
                }
            }
        }

        return !refTokenNegative || otherTokensZero;
    }

    function calculateInterest(
        int256 mode,
        string memory tokenName,
        int256 balance,
        uint256 startInterval,
        uint256 endInterval
    )
        private
        view
        returns (
            uint256 interest,
            uint256 start,
            uint256 num
        )
    {
        if ((mode == Mode.DEALER_MODE) || (balance >= 0)) {
            return (0, 0, 0);
        }

        PoolStruct.Token storage t = tokens[tokenName];
        uint256 tokenDecimal = uint256(ERC20(address(t.tokenAddr)).decimals());

        // This is to find the last interest rate history used in calculation
        uint256 end = t.interestRates.length - 1;
        while (true) {
            if (t.interestRates[end].effectiveTime <= endInterval) {
                break;
            }

            if (end == 0) {
                break;
            }

            --end;
        }

        // Initial condition
        interest = 0;
        uint256 loan = uint256(-balance);
        int256 pos = int256(end);
        uint256 cur = endInterval;
        uint256 _interestInterval = interestInterval;

        while (true) {
            PoolStruct.InterestRate memory r = t.interestRates[uint256(pos)];
            uint256 effectiveTime = r.effectiveTime;

            // If the first interest rate setting takes effect after start interval
            // Assume also use the first rate for that period
            // This should not be happened practically, but just to prevent chance of referencing to negative index of array
            if ((effectiveTime > startInterval) && pos >= 0) {
                {
                    // The pointing interest rate took effective after startInterval, calculate interest up to its effective time, then continue to the previous
                    uint256 period = ((cur - effectiveTime) / _interestInterval) + 1;
                    interest = cumulativeInterest(interest, period, loan, r.value, tokenDecimal, t.effectiveDecimal);
                }

                cur = effectiveTime.sub(_interestInterval);
                --pos;
            } else {
                {
                    // Note that here does not +1, because interest at the time of startInterval should be already settled
                    uint256 period = (cur - startInterval) / _interestInterval;
                    interest = cumulativeInterest(interest, period, loan, r.value, tokenDecimal, t.effectiveDecimal);
                }

                start = pos <= 0 ? 0 : uint256(pos);
                num = end - start + 1;
                break;
            }
        }
    }

    function cumulativeInterest(
        uint256 interest,
        uint256 period,
        uint256 loan,
        uint256 rate,
        uint256 tokenDecimal,
        uint256 effectiveDecimal
    ) private pure returns (uint256) {
        // Calculate interest of single period
        // Interest rate decimal is 9
        // The basic form to calculate interest is
        // loan * rate / 1000000000
        // However, to prevent double rounding when taking effective decimal into account
        // Suppose token decimal (D) = 18, effective decimal (d) = 6
        //                      loan * rate = 987 123 455 888 777 666 555 444 333 222
        //                  actual interest = 987 123 455 888 777 666 555 (987.123455888777666555 ETHM)
        // expected output of this function = 987 123 456 000 000 000 000 (987.123456 ETHM)
        // The calculation becomes
        // 1. Think loan * rate as float number, divide it by 10^21 (10**(9+D-d))
        // 987 123 455.888 777 666 555 444 333 222
        // 2. Round it
        // 987 123 456
        // 3. Multiply by 10^12 (10**(D-d))
        // 987 123 456 000 000 000 000
        uint256 denominator;
        uint256 multiplier;
        {
            uint256 D = tokenDecimal;
            uint256 d = effectiveDecimal <= tokenDecimal ? effectiveDecimal : tokenDecimal;
            denominator = 10**(9 + D - d);
            multiplier = 10**(D - d);
        }
        uint256 i = loan.mul(rate).add(denominator >> 1).div(denominator).mul(multiplier);

        // Then multiply the period and return cumulative
        return i.mul(period).add(interest);
    }

    function getReferenceTokenEquivalent(address tokenAddr, int256 balance) internal view returns (int256) {
        (IRaijinSwapRouter _router, address _refToken) = (router, address(refToken));
        if (balance == 0) {
            return 0;
        } else if (tokenAddr == _refToken) {
            return balance;
        } else {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(IUniswapV2Factory(_router.factory()).getPair(_refToken, tokenAddr)).getReserves();
            uint256 amount = balance >= 0 ? uint256(balance) : uint256(-balance);
            uint256 out = tokenAddr < _refToken ? _router.quote(amount, reserve0, reserve1) : _router.quote(amount, reserve1, reserve0);
            return balance >= 0 ? int256(out) : -int256(out);
        }
    }

    function balanceForDisplay(string memory tokenName, int256 balance) private view returns (int256) {
        // Trivial case
        if (balance == 0) {
            return 0;
        }

        PoolStruct.Token memory t = tokens[tokenName];
        uint256 tokenDecimal = uint256(ERC20(address(t.tokenAddr)).decimals());

        // No need to do rounding
        if (tokenDecimal <= t.effectiveDecimal) {
            return balance;
        }

        int256 denominator = int256(10**(tokenDecimal - t.effectiveDecimal));

        // The balance for display is always round-down of actual value
        if (balance > 0) {
            return balance.div(denominator).mul(denominator);
        } else {
            // Negate the value, round up, then negate again
            return (-balance).add(denominator - 1).div(denominator).mul(-denominator);
        }
    }

    function calculateRiskLevel(
        address customer,
        uint256 usedFunding,
        int256 equity
    ) private view returns (int256) {
        // Prevent divide by 0
        if (usedFunding == 0) {
            return 0;
        }

        PoolStruct.Customer storage c = customers[customer];

        // Smallest risk level is 0, the larger the higher risk
        // Decimal of leverage is 3; decimal of risk level is 6
        int256 r = equity.mul(int256(c.leverage)).add(c.mode == Mode.DEALER_MODE ? int256(c.maxFunding).mul(1000) : 0).mul(1000).div(int256(usedFunding));
        return r >= 1000000 ? 0 : int256(1000000).sub(r);
    }

    function checkPairAndGetOtherTokenName(string memory pairName, string memory tokenName) private view returns (string memory) {
        PoolUtilities.pairMustExist(pairList, pairName);

        PoolStruct.Pair storage p = pairs[pairName];
        require(p.enabled, "Pair is disabled");

        if (p.token0Name.equals(tokenName)) {
            return p.token1Name;
        } else {
            return p.token0Name;
        }
    }

    modifier onlyBackend() {
        require(hasRole(Constant.BACKEND_ROLE, msg.sender), "Backend only");
        _;
    }

    modifier onlyDeployer() {
        require(hasRole(Constant.DEPLOYER_ROLE, msg.sender), "Deployer only");
        _;
    }

    modifier onlyCustomerThemself(address customer) {
        require(msg.sender == customer, "No permission");
        _;
    }

    function customerNotDisabled(address customer) private view {
        require(customers[customer].status != CustomerStatus.DISABLED, "Customer is disabled");
    }

    modifier nonReentrant() {
        require(reentrancyState != Constant.ENTERED, "ReentrancyGuard: reentrant call");

        reentrancyState = Constant.ENTERED;
        _;
        reentrancyState = Constant.NOT_ENTERED;
    }

    /* Some logic is split into other contract */

    function getDeployers() external view override returns (address[] memory) {
        uint256 count = getRoleMemberCount(Constant.DEPLOYER_ROLE);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(Constant.DEPLOYER_ROLE, i);
        }
        return members;
    }

    function grantDeployer(address deployerAddr) external override onlyOwner {
        grantRole(Constant.DEPLOYER_ROLE, deployerAddr);
    }

    function revokeDeployer(address deployerAddr) external override onlyOwner {
        revokeRole(Constant.DEPLOYER_ROLE, deployerAddr);
    }

    function getManagementContract() public view override returns (address c) {
        bytes32 slot = Constant.MANAGEMENT_CONTRACT_SLOT;
        assembly {
            c := sload(slot)
        }
    }

    function setManagementContract(address newManagementContract) external override onlyDeployer {
        require(Address.isContract(newManagementContract), "Address is not a contract");

        bytes32 slot = Constant.MANAGEMENT_CONTRACT_SLOT;
        assembly {
            sstore(slot, newManagementContract)
        }
    }

    fallback() external payable {
        delegate();
    }

    receive() external payable {
        delegate();
    }

    function delegate() private {
        address implementation = getManagementContract();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
