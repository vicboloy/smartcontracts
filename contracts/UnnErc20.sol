pragma solidity ^0.6.0;

import "./UnnToken.sol";
import "./UnnTokenInterface.sol";

contract UnnErc20 is UnnToken, UnnErc20Interface {
	
	// address public underlyingAsset;

	function initialize(address _underlyingAsset, 
                        InterestRateModel _interestRateModel,
						string memory _name, 
						string memory _symbol, 
						uint8 _decimals,
                        uint256 _initialExchangeRateMultiplier) public {

		super.initialize(_initialExchangeRateMultiplier, _interestRateModel, _name, _symbol, _decimals);
		underlyingAsset = _underlyingAsset;
        EIP20StandardInterface(underlyingAsset).totalSupply();
	}

	function mint(uint256 _mintAmount) external override returns (uint256) {
		(uint256 err,) = mintToken(msg.sender, _mintAmount);
		return err;
	}

	function redeem(uint256 _redeemTokens) external override returns (uint256) {
        return redeemInternal(_redeemTokens);
    }

    function redeemUnderlying(uint256 _redeemAmount) external override returns (uint256) {
        return redeemUnderlyingInternal(_redeemAmount);
    }

    /**
      * @notice Sender borrows assets from the protocol to their own address
      * @param _borrowAmount The amount of the underlying asset to borrow
      * @return uint256 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function borrow(uint256 _borrowAmount) external override returns (uint256) {
        return borrowToken(msg.sender, _borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param _repayAmount The amount to repay
     * @return uint256 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint256 _repayAmount) external override returns (uint256) {
        (uint err,) = repayBorrowInternal(_repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param _borrower the account with the debt being payed off
     * @param _repayAmount The amount to repay
     * @return uint256 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(address _borrower, uint256 _repayAmount) external override returns (uint256) {
        (uint err,) = repayBorrowBehalfInternal(_borrower, _repayAmount);
        return err;
    }

    function getBalanceUnderlying() internal view override returns (uint256) {
    	EIP20StandardInterface token = EIP20StandardInterface(underlyingAsset);
    	return token.balanceOf(address(this));	
    }

	function doTransferIn(address _from, uint256 _amount) internal override returns (uint256) {
		EIP20StandardInterface token = EIP20StandardInterface(underlyingAsset);
		uint256 balanceBefore = EIP20StandardInterface(underlyingAsset).balanceOf(address(this));
		token.transferFrom(_from, address(this), _amount);

		bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        uint256 balanceAfter = EIP20StandardInterface(underlyingAsset).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore;
	}

	function doTransferOut(address payable _to, uint256 _amount) internal override {
        EIP20StandardInterface token = EIP20StandardInterface(underlyingAsset);
        token.transfer(_to, _amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                      // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                     // This is a complaint ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                     // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }
}