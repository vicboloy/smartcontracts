pragma solidity ^0.6.0;

/**
  * @title Custom Safe Math
  * @notice Derived from OpenZeppelin's SafeMath library
  *         https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol
  */
contract CustomSafeMath {

	/**
     * @dev Possible error codes that we can return
     */
    enum MathError {
        NO_ERROR,
        DIVISION_BY_ZERO,
        ADDITION_OVERFLOW,
        SUBTRACTION_OVERFLOW,
        MULTIPLICATION_OVERFLOW,
        MODULO_BY_ZERO
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns(MathError, uint256) {
    	uint256 c = a + b;
    	if(c >= a) {
    		return (MathError.NO_ERROR, c);
    	} else {
    		return (MathError.ADDITION_OVERFLOW, 0);
    	}
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (MathError, uint256) {
    	if(b <= a) {
    		return (MathError.NO_ERROR, a -b);
    	} else {
    		return (MathError.SUBTRACTION_OVERFLOW, 0);
    	}
    }

    function safeMul(uint256 a, uint256 b) internal pure returns (MathError, uint256) {
    	if (a == 0) {
    		return (MathError.NO_ERROR, 0);
    	}

    	uint256 c = a * b;
    	if(c / a == b) {
    		return (MathError.NO_ERROR, c);
    	} else {
    		return (MathError.MULTIPLICATION_OVERFLOW, 0);
    	}
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (MathError, uint256) {
    	uint256 c = a / b;
    	if(b > 0) {
    		return (MathError.NO_ERROR, c);
    	} else {
    		return (MathError.DIVISION_BY_ZERO, 0);
    	}
    }

    function safeMod(uint256 a, uint256 b) internal pure returns (MathError, uint256) {
    	if(b != 0) {
    		return (MathError.NO_ERROR, a % b);
    	} else {
    		return (MathError.MODULO_BY_ZERO, 0);
    	}
    }

    function safeAddThenSub(uint256 a, uint256 b, uint256 c) internal pure returns (MathError, uint256) {
    	(MathError error, uint256 sum) = safeAdd(a, b);

    	if(error != MathError.NO_ERROR) {
    		return (error, 0);
    	} 

    	return safeSub(sum, c);
    }

}