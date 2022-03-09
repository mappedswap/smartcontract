pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

interface IPoolTrading {
    function withdraw(string calldata tokenName, uint256 amount) external;

    function withdrawTo(
        address toCustomer,
        string calldata tokenName,
        uint256 amount
    ) external;

    function buy(
        address customer,
        string calldata pairName,
        string calldata tokenNameBuy,
        uint256 amountBuy,
        uint256 amountSellMax,
        uint256 deadline
    ) external;

    function sell(
        address customer,
        string calldata pairName,
        string calldata tokenNameSell,
        uint256 amountSell,
        uint256 amountBuyMin,
        uint256 deadline
    ) external;

    event IncreaseBalance(address indexed customer, string tokenName, uint256 amount, int256 newBalance);

    event Withdraw(address indexed customer, string tokenName, uint256 amount, int256 newBalance);

    event Buy(address indexed customer, string pairName, string tokenNameBuy, uint256 amountBuy, int256 newBalanceBuy, uint256 amountSell, int256 newBalanceSell, bool isStopout);

    event Sell(address indexed customer, string pairName, string tokenNameSell, uint256 amountSell, int256 newBalanceSell, uint256 amountBuy, int256 newBalanceBuy, bool isStopout);

    event Interest(address indexed customer, uint256 beginTime, uint256 endTime, string[] tokenNames, int256[] realizedBalances, uint256[] interests);
}
