pragma solidity ^0.6.0;

import "./CustomSafeMath.sol";

contract ExchangeRate is CustomSafeMath {
	uint256 constant expScale = 1e18;
    uint256 constant doubleScale = 1e36;
    uint256 constant halfExpScale = expScale/2;
    uint256 constant exchangeRateMultiplier = expScale;

    struct StoredExchangeRate {
        uint256 exchange;
    }

    function getExchangeRateStored(uint256 num, uint256 denom) pure internal returns (MathError, StoredExchangeRate memory) {
        (MathError err0, uint256 scaledNumerator) = safeMul(num, expScale);
        if (err0 != MathError.NO_ERROR) {
            return (err0, StoredExchangeRate({exchange: 0}));
        }

        (MathError err1, uint256 rational) = safeMul(scaledNumerator, denom);
        if (err1 != MathError.NO_ERROR) {
            return (err1, StoredExchangeRate({exchange: 0}));
        }

        return (MathError.NO_ERROR, StoredExchangeRate({exchange: rational}));
    }

    function divScalar(uint256 scalar, StoredExchangeRate memory divisor) pure internal returns (MathError, StoredExchangeRate memory) {
    	(MathError error, uint256 numerator) = safeMul(expScale, scalar);
    	if(error != MathError.NO_ERROR) {
    		return (error, StoredExchangeRate({exchange: 0}));
    	} 
    	return getExchangeRateStored(numerator, divisor.exchange);
    }

    function divScalarThenTruncate(uint256 scalar, StoredExchangeRate memory divisor) pure internal  returns (MathError, uint256) {
    	(MathError error, StoredExchangeRate memory fraction) = divScalar(scalar, divisor);
    	if (error != MathError.NO_ERROR) {
            return (error, 0);
        }

        return (MathError.NO_ERROR, truncate(fraction));
    }

    function mulScalar(StoredExchangeRate memory a, uint256 scalar) pure internal returns (MathError, StoredExchangeRate memory) {
        (MathError err0, uint256 scaledMantissa) = safeMul(a.exchange, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, StoredExchangeRate({exchange: 0}));
        }

        return (MathError.NO_ERROR, StoredExchangeRate({exchange: scaledMantissa}));
    }

    function mulScalarThenTruncate(StoredExchangeRate memory a, uint256 scalar) pure internal returns (MathError, uint256) {
        (MathError err, StoredExchangeRate memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, truncate(product));
    }

    function mulScalarThenTruncateThenAdd(StoredExchangeRate memory a, uint scalar, uint addend) pure internal returns (MathError, uint) {
        (MathError err, StoredExchangeRate memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return safeAdd(truncate(product), addend);
    }

    function truncate(StoredExchangeRate memory exchangeRate) pure internal returns (uint256) {
        return exchangeRate.exchange / expScale;
    }

}