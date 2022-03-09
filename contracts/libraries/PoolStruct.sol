pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/swap/IUniswapV2Pair.sol";

library PoolStruct {
    struct Customer {
        // When calling view functions, need to calculate interest
        // When making transaction, please keep all balances to most updated values at the end
        mapping(string => int256) balances;
        // Max funding, changes only if agent updates it
        // Decimal is 6, same as USDM
        uint256 maxFunding;
        // Stopout risk level, changes only if agent updates it
        // Decimal is 6, so if risk level is 50%, this value should be 500000
        int256 riskLevel;
        // Always divisible by INTEREST_INTERVAL, currently this means interests are calculated hourly
        uint256 lastInterestCalcTime;
        int256 status;
        int256 mode;
        uint256 leverage;
    }

    struct CustomerTokenInfo {
        string tokenName;
        int256 realizedBalance;
        InterestRate[] interestRates;
        uint256 interest;
        int256 usdmEquivalent;
    }

    // For returning to caller use, includes dynamically calculated fields
    struct CustomerInfo {
        CustomerTokenInfo[] tokens;
        int256 equity;
        int256 mode;
        uint256 leverage;
        uint256 maxFunding;
        uint256 usedFunding;
        int256 stopoutRiskLevel;
        int256 currentRiskLevel;
        uint256 lastInterestCalcTime;
        uint256 interestCalcCutoffTime;
        int256 status;
    }

    struct InterestRate {
        // Decimal of interest rate is 9, so if set to 0.01% interest, value should be 100000 (0.01% => 0.0001, then * 10^9 = 100000)
        uint256 value;
        uint256 effectiveTime;
    }

    // Storage and info returning to caller can share the same struct
    struct Token {
        IERC20 tokenAddr;
        InterestRate[] interestRates;
        uint256 effectiveDecimal;
    }

    struct Pair {
        // Reverse name for quick look up in mapping
        string reversePairName;
        string token0Name;
        string token1Name;
        IERC20 token0Addr;
        IERC20 token1Addr;
        IUniswapV2Pair pairAddr;
        bool enabled;
    }

    // For returning to caller use, values mostly come from IUniswapV2Pair
    struct PairInfo {
        IUniswapV2Pair pairAddr;
        string token0Name;
        string token1Name;
        IERC20 token0Addr;
        IERC20 token1Addr;
        uint112 reserve0;
        uint112 reserve1;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 blockTimestampLast;
        bool enabled;
    }
}
