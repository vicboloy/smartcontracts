pragma solidity ^0.6.0;

import "./InterestRateModel.sol";

abstract contract UnnTokenInterface {

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
     * @notice Maximum borrow rate that can ever be applied (.0005% / block)
     */
    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    InterestRateModel public interestRateModel;

    /**
     * @notice Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
     */
    uint256 internal initialExchangeRateMultiplier;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint public reserveFactorMultiplier;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint public accrualBlkNo;

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    uint256 public borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint256 public totalBorrows;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint256 public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint256 public totalSupply;

    mapping (address => uint256) internal accountTokens;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }


    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping (address => mapping (address => uint)) internal transferAllowances;


    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
    * @notice Event emitted when tokens are minted
    */
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens);

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /**
     * @notice Failure event
     */
    event Failure(uint error, uint info, uint detail);

    function transfer(address _dst, uint256 _amount) virtual external returns (bool);
    function transferFrom(address _src, address _dst, uint256 _amount) virtual external returns (bool);
    function approve(address _spender, uint256 _amount) virtual external returns (bool);
    function allowance(address _owner, address _spender) virtual external view returns (uint256);
    function balanceOf(address _owner) virtual external view returns (uint256);
    function balanceOfUnderlying(address _owner) virtual external returns (uint256);
    function exchangeRateCurrent() virtual public returns (uint256);
    function exchangeRateStored() virtual public view returns (uint256);
    function getCash() virtual external view returns (uint256);
}

abstract contract UnnErc20Interface {

    address public underlyingAsset;

    /*** User Interface ***/

    function mint(uint256 _mintAmount) virtual external returns (uint256);
    function redeem(uint256 _redeemTokens) virtual external returns (uint256);
    function redeemUnderlying(uint256 _redeemAmount) virtual external returns (uint256);
    function borrow(uint256 _borrowAmount) virtual external returns (uint256);
    function repayBorrow(uint256 _repayAmount) virtual external returns (uint256);
    function repayBorrowBehalf(address _borrower, uint256 _repayAmount) virtual external returns (uint256);


    // /*** Admin Functions ***/

    // function _addReserves(uint256 addAmount) external returns (uint256);
}