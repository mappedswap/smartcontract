pragma solidity =0.6.6;

interface IPoolStopout {
    function stopout(address customer) external;

    event Stopout(address indexed customer, int256 stopoutEquity, uint256 stopoutFunding, int256 finalBalance);

    event Loss(address indexed customer, uint256 amount, uint256 cumulativeLoss);
}
