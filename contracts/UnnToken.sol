pragma solidity ^0.6.0;

import "./UnnTokenInterface.sol";
import "./ExchangeRate.sol";
import "./ErrorHandler.sol";
import "./InterestRateModel.sol";
import "./EIP20StandardInterface.sol";

import "@openzeppelin/contracts/GSN/Context.sol";

abstract contract UnnToken is UnnTokenInterface, ExchangeRate, ErrorHandler {


    function initialize(uint256 _initialExchangeRateMultiplier,
                        InterestRateModel _interestRateModel,
    					string memory _name,
                        string memory _symbol,
                        uint8 _decimals) public {
        require(accrualBlkNo == 0 && borrowIndex == 0, "market may only be initialized once");

    	//Set initial exchange rate non-zero.
    	initialExchangeRateMultiplier = _initialExchangeRateMultiplier;
    	require(initialExchangeRateMultiplier > 0, "initial exchange rate must be greater than zero.");

        accrualBlkNo = getBlockNumber();
        borrowIndex = exchangeRateMultiplier;

        // Set the interest rate model (depends on block number / borrow index)
        uint256 err = _setInterestRateModelFresh(_interestRateModel);
        require(err == uint256(Error.NO_ERROR), "setting interest rate model failed");

    	name = _name;
    	symbol = _symbol;
    	decimals = _decimals;
    }


    /**
     * @notice Transfer `tokens` tokens from `_src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param _spender The address of the account performing the transfer
     * @param _src The address of the source account
     * @param _dst The address of the destination account
     * @param _tokens The number of _tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferTokens(address _spender, address _src, address _dst, uint256 _tokens) internal returns (uint256) {

        /* Do not allow self-transfers */
        if (_src == _dst) {
            return fail(Error.BAD_INPUT, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance = 0;
        if (_spender == _src) {
            startingAllowance = uint256(-1);
        } else {
            startingAllowance = transferAllowances[_src][_spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        MathError mathErr;
        uint256 allowanceNew;
        uint256 srcTokensNew;
        uint256 dstTokensNew;

        (mathErr, allowanceNew) = safeSub(startingAllowance, _tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        (mathErr, srcTokensNew) = safeSub(accountTokens[_src], _tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ENOUGH);
        }

        (mathErr, dstTokensNew) = safeAdd(accountTokens[_dst], _tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_TOO_MUCH);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[_src] = srcTokensNew;
        accountTokens[_dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != uint256(-1)) {
            transferAllowances[_src][_spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(_src, _dst, _tokens);

        // comptroller.transferVerify(address(this), src, dst, tokens);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param _dst The address of the destination account
     * @param _amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address _dst, uint256 _amount) external override returns (bool) {
        return transferTokens(msg.sender, msg.sender, _dst, _amount) == uint256(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param _src The address of the source account
     * @param _dst The address of the destination account
     * @param _amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address _src, address _dst, uint256 _amount) external override returns (bool) {
        return transferTokens(msg.sender, _src, _dst, _amount) == uint256(Error.NO_ERROR);
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param _spender The address of the account which may transfer tokens
     * @param _amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address _spender, uint256 _amount) external override returns (bool) {
        address src = msg.sender;
        transferAllowances[src][_spender] = _amount;
        emit Approval(src, _spender, _amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param _owner The address of the account which owns the tokens to be spent
     * @param _spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return transferAllowances[_owner][_spender];
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param _owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address _owner) external view override returns (uint256) {
        return accountTokens[_owner];
    }

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param _owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address _owner) external override returns (uint256) {
        StoredExchangeRate memory exchangeRate = StoredExchangeRate({exchange: exchangeRateCurrent()});
        (MathError mErr, uint256 balance) = mulScalarThenTruncate(exchangeRate, accountTokens[_owner]);
        require(mErr == MathError.NO_ERROR, "balance could not be calculated");
        return balance;
    }

    function exchangeRateCurrent() public override returns (uint256) {
        return exchangeRateStored();
    }

    function exchangeRateStored() public view override returns (uint256) {
        (MathError err, uint256 result) = getExchangeRate();
        require(err == MathError.NO_ERROR, "exchangeRateStored: exchangeRateStoredInternal failed");
        return result;
    }

    function getExchangeRate() internal view returns (MathError, uint256) {

    	if(totalSupply == 0) {
    		return (MathError.NO_ERROR, initialExchangeRateMultiplier);
    	} else {


    		uint256 totalBalanceUnderlying = getBalanceUnderlying();
    		uint256 totalCashBorrowsReserves;
    		StoredExchangeRate memory exchangeRate;
    		MathError error;

    		(error, totalCashBorrowsReserves) = safeAddThenSub(totalBalanceUnderlying, totalBorrows, totalReserves);
    		if(error != MathError.NO_ERROR) {
    			return (error, 0);
    		}

    		(error, exchangeRate) = getExchangeRateStored(totalCashBorrowsReserves, totalSupply);
    		if(error != MathError.NO_ERROR) {
    			return (error, 0);
    		}

    		return (MathError.NO_ERROR, exchangeRate.exchange);
    	}
    }

    /**
     * @notice Get cash balance of this cToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view override returns (uint256) {
        return getBalanceUnderlying();
    }

    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }

    function borrowBalanceStoredInternal(address account) internal view  returns (MathError, uint256) {
        MathError mathErr;
        uint256 principalTimesIndex;
        uint256 result;

        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        if (borrowSnapshot.principal == 0) {
            return (MathError.NO_ERROR, 0);
        }

        (mathErr, principalTimesIndex) = safeMul(borrowSnapshot.principal, borrowIndex);
        if(mathErr != MathError.NO_ERROR) {
            return (MathError.NO_ERROR, 0);
        }

        (mathErr, result) = safeDiv(principalTimesIndex, borrowSnapshot.interestIndex);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        return (MathError.NO_ERROR, result);
    }

    function accrueInterest() public returns (uint256) {
    	uint256 currentBlkNo = getBlockNumber();
    	uint256 prevAccrualBlkNo = accrualBlkNo;

    	if(prevAccrualBlkNo == currentBlkNo) {
    		return (uint256(Error.NO_ERROR));
    	}

    	uint256 _cashPrior = getBalanceUnderlying();
    	uint256 _totalBorrows = totalBorrows;
    	uint256 _totalReserves = totalReserves;
    	uint256 _borrowIndex = borrowIndex;
        MathError mathErr;

    	uint256 borrowRate = interestRateModel.getBorrowRate(_cashPrior, _totalBorrows, _totalReserves);
        require(borrowRate <= borrowRateMaxMantissa, "borrow rate is absurdly high");

        uint256 blkDiff;
    	(mathErr, blkDiff) = safeSub(currentBlkNo, prevAccrualBlkNo);
    	require(mathErr == MathError.NO_ERROR, "Could not calculate block difference");

    	StoredExchangeRate memory simpleInterestFactor;

        (mathErr, simpleInterestFactor) = mulScalar(StoredExchangeRate({exchange: borrowRate}), blkDiff);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_SIMPLE_INTEREST_FACTOR_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 interestAccumulated;
        (mathErr, interestAccumulated) = mulScalarThenTruncate(simpleInterestFactor, _totalBorrows);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_ACCUMULATED_INTEREST_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 newTotalBorrows;
        (mathErr, newTotalBorrows) = safeAdd(interestAccumulated, _totalBorrows);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_TOTAL_BORROWS_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 newTotalReserves;
        (mathErr, newTotalReserves) = mulScalarThenTruncateThenAdd(StoredExchangeRate({exchange: reserveFactorMultiplier}), interestAccumulated, _totalReserves);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_TOTAL_RESERVES_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 borrowIndexNew;
        (mathErr, borrowIndexNew) = mulScalarThenTruncateThenAdd(simpleInterestFactor, _borrowIndex, _borrowIndex);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_BORROW_INDEX_CALCULATION_FAILED, uint256(mathErr));
        }

        /* We write the previously calculated values into storage */
        accrualBlkNo = currentBlkNo;
        borrowIndex = borrowIndexNew;
        totalBorrows = newTotalBorrows;
        totalReserves = newTotalReserves;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(_cashPrior, interestAccumulated, borrowIndexNew, newTotalBorrows);

        return uint256(Error.NO_ERROR);

    }

    function mintToken(address _minter, uint256 _mintAmount) internal returns (uint256, uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.MINT_ACCRUE_INTEREST_FAILED), 0);
        }
    	MathError mathErr;

    	//TODO: Mint allowed checker

    	if (accrualBlkNo != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.MINT_FRESHNESS_CHECK), 0);
        }

        uint256 exchangeRate;
    	(mathErr, exchangeRate) = getExchangeRate();
        if (mathErr != MathError.NO_ERROR) {
            return (failOpaque(Error.MATH_ERROR, FailureInfo.MINT_EXCHANGE_RATE_READ_FAILED, uint256(mathErr)), 0);
        }

		uint256 actualMintAmount = doTransferIn(msg.sender, _mintAmount);

        uint256 mintTokens;
		(mathErr, mintTokens) = divScalarThenTruncate(actualMintAmount, StoredExchangeRate({exchange: exchangeRate}));
        require(mathErr == MathError.NO_ERROR, "MINT_EXCHANGE_CALCULATION_FAILED");

        uint256 totalSupplyNew;
        (mathErr, totalSupplyNew) = safeAdd(totalSupply, mintTokens);
        require(mathErr == MathError.NO_ERROR, "MINT_NEW_TOTAL_SUPPLY_CALCULATION_FAILED");

        uint256 accountTokensNew;
        (mathErr, accountTokensNew) = safeAdd(accountTokens[msg.sender], mintTokens);
        require(mathErr == MathError.NO_ERROR, "MINT_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED");

        /* We write previously calculated values into storage */
        totalSupply = totalSupplyNew;
        accountTokens[msg.sender] = accountTokensNew;

        emit Mint(_minter, actualMintAmount, mintTokens);
        emit Transfer(address(this), _minter, mintTokens);

        //TODO: Mint verifier

        return (uint256(Error.NO_ERROR), actualMintAmount);
	}

	function redeemInternal(uint256 _redeemTokens) internal returns (uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
		return redeemToken(msg.sender, _redeemTokens, 0);
	}

	function redeemUnderlyingInternal(uint256 _redeemAmount) internal returns (uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
		return redeemToken(msg.sender, 0, _redeemAmount);
    }

    function redeemToken(address payable _redeemer, uint256 _redeemTokens, uint256 _redeemAmount) internal returns (uint256) {
    	require(_redeemTokens == 0 || _redeemAmount == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

    	MathError mathErr;
        uint256 redeemTokens;
        uint256 redeemAmount;

        uint256 exchangeRate;
    	(mathErr, exchangeRate) = getExchangeRate();
    	if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_RATE_READ_FAILED, uint256(mathErr));
        }

    	if(redeemTokens > 0) {
    		redeemTokens = _redeemTokens;
    		(mathErr, redeemAmount) = mulScalarThenTruncate(StoredExchangeRate({exchange: exchangeRate}), _redeemTokens);
    		if (mathErr != MathError.NO_ERROR) {
                return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED, uint256(mathErr));
            }
    	} else {
    		(mathErr, redeemTokens) = divScalarThenTruncate(_redeemAmount, StoredExchangeRate({exchange: exchangeRate}));
            if (mathErr != MathError.NO_ERROR) {
                return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED, uint256(mathErr));
            }
    		redeemAmount = redeemAmount;
    	}

    	//TODO: Redeem allowed checker

    	if (accrualBlkNo != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.REDEEM_FRESHNESS_CHECK);
        }

        uint256 totalSupplyNew;
    	(mathErr, totalSupplyNew) = safeSub(totalSupply, redeemTokens);
    	if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_NEW_TOTAL_SUPPLY_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 accountTokensNew;
    	(mathErr, accountTokensNew) = safeSub(accountTokens[_redeemer], redeemTokens);
    	if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED, uint256(mathErr));
        }

    	if(getBalanceUnderlying() < redeemAmount) {
    		return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.REDEEM_TRANSFER_OUT_NOT_POSSIBLE);
    	}

    	doTransferOut(msg.sender, redeemTokens);

    	 /* We write previously calculated values into storage */
        totalSupply = totalSupplyNew;
        accountTokens[_redeemer] = accountTokensNew;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(_redeemer, address(this), redeemTokens);
        emit Redeem(_redeemer, redeemAmount, redeemTokens);

        //TODO: Redeem verifier

        return uint256(Error.NO_ERROR);
    }

    function borrowToken(address payable _borrower, uint256 _borrowAmount) internal returns (uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return fail(Error(error), FailureInfo.BORROW_ACCRUE_INTEREST_FAILED);
        }
    	//TODO: Redeem allowed checker

    	/* Verify market's block number equals current block number */
        if (accrualBlkNo != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.BORROW_FRESHNESS_CHECK);
        }

    	if(getBalanceUnderlying() < _borrowAmount) {
    		return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.BORROW_CASH_NOT_AVAILABLE);
    	}

    	MathError mathErr;

        uint256 _accountBorrows;
    	(mathErr, _accountBorrows) = borrowBalanceStoredInternal(_borrower); //TODO function
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 _accountBorrowsNew;
        (mathErr, _accountBorrowsNew) = safeAdd(_accountBorrows, _borrowAmount);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED, uint256(mathErr));
        }

        uint256 _totalBorrowsNew;
        (mathErr, _totalBorrowsNew) = safeAdd(totalBorrows, _borrowAmount);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED, uint256(mathErr));
        }

        doTransferOut(_borrower, _borrowAmount);

        /* We write the previously calculated values into storage */
        accountBorrows[_borrower].principal = _accountBorrowsNew;
        accountBorrows[_borrower].interestIndex = borrowIndex;
        totalBorrows = _totalBorrowsNew;

        /* We emit a Borrow event */
        emit Borrow(_borrower, _borrowAmount, _accountBorrowsNew, _totalBorrowsNew);

        //TODO: Redeem verifier

        return uint256(Error.NO_ERROR);

    }

    /**
     * @notice Sender repays their own borrow
     * @param _repayAmount The amount to repay
     * @return (uint256, uint256) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowInternal(uint256 _repayAmount) internal returns (uint256, uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.REPAY_BORROW_ACCRUE_INTEREST_FAILED), 0);
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowToken(msg.sender, msg.sender, _repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param _borrower the account with the debt being payed off
     * @param _repayAmount The amount to repay
     * @return (uint256, uint256) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowBehalfInternal(address _borrower, uint256 _repayAmount) internal returns (uint256, uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.REPAY_BEHALF_ACCRUE_INTEREST_FAILED), 0);
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowToken(msg.sender, _borrower, _repayAmount);
    }

    function repayBorrowToken(address _payer, address _borrower, uint256 _repayAmount) internal returns (uint256, uint256) {
    	//TODO: Repay allowed checker

    	/* Verify market's block number equals current block number */
        if (accrualBlkNo != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.REPAY_BORROW_FRESHNESS_CHECK), 0);
        }

    	MathError mathErr;
        uint256 repayAmount;

    	uint256 borrowerIndex = accountBorrows[_borrower].interestIndex;

        uint256 _accountBorrows;
    	(mathErr, _accountBorrows) = borrowBalanceStoredInternal(_borrower); // TODO function
    	if (mathErr != MathError.NO_ERROR) {
            return (failOpaque(Error.MATH_ERROR, FailureInfo.REPAY_BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED, uint256(mathErr)), 0);
        }

    	/* If repayAmount == -1, repayAmount = accountBorrows */
        if (_repayAmount == uint256(-1)) {
            repayAmount = _accountBorrows;
        } else {
            repayAmount = _repayAmount;
        }

        uint256 actualRepayAmount = doTransferIn(_payer, repayAmount);

        uint256 accountBorrowsNew;
        (mathErr, accountBorrowsNew) = safeSub(_accountBorrows, actualRepayAmount);
        require(mathErr == MathError.NO_ERROR, "REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED");

        uint256 totalBorrowsNew;
        (mathErr, totalBorrowsNew) = safeSub(totalBorrows, actualRepayAmount);
        require(mathErr == MathError.NO_ERROR, "REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED");

        /* We write the previously calculated values into storage */
        accountBorrows[_borrower].principal = accountBorrowsNew;
        accountBorrows[_borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(_payer, _borrower, actualRepayAmount, accountBorrowsNew, totalBorrowsNew);

        //TODO: Repay verifier 

        return (uint256(Error.NO_ERROR), actualRepayAmount);
    }

    /**
     * @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     * @return uint256 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint256) {
        uint256 error = accrueInterest();
        if (error != uint256(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted change of interest rate model failed
            return fail(Error(error), FailureInfo.SET_INTEREST_RATE_MODEL_ACCRUE_INTEREST_FAILED);
        }
        // _setInterestRateModelFresh emits interest-rate-model-update-specific logs on errors, so we don't need to.
        return _setInterestRateModelFresh(newInterestRateModel);
    }

    /**
     * @notice updates the interest rate model (*requires fresh interest accrual)
     * @dev Admin function to update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     * @return uint256 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal returns (uint256) {

        // Used to store old model for use in the event that is emitted on success
        InterestRateModel oldInterestRateModel;

        // Check caller is admin
        // if (msg.sender != admin) {
        //     return fail(Error.UNAUTHORIZED, FailureInfo.SET_INTEREST_RATE_MODEL_OWNER_CHECK);
        // }

        // We fail gracefully unless market's block number equals current block number
        if (accrualBlkNo != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.SET_INTEREST_RATE_MODEL_FRESH_CHECK);
        }

        // Track the market's current interest rate model
        oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        require(newInterestRateModel.isInterestRateModel(), "marker method returned false");

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel);

        return uint256(Error.NO_ERROR);
    }


    function getBalanceUnderlying() virtual internal view returns (uint256);

    function doTransferIn(address from, uint256 amount) virtual internal returns (uint256);

    function doTransferOut(address payable to, uint256 amount) virtual internal;


}