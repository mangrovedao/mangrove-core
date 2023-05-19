// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

/**
 * @notice This contract provides a collection of interactions capabilities with AAVE-v3 to whichever contract inherits it
 */
/**
 * `AaveV3Borrower` contracts are in particular able to perfom basic pool interactions (lending, borrowing, supplying and repaying)
 */
/**
 * @dev it is designed with a diamond storage scheme where core function implementations are delegated to an immutable `IMPLEMENTATION` address
 */

import {AaveV3Lender} from "./AaveV3Lender.sol";
import {AaveV3BorrowerStorage as AMS} from "./AaveV3BorrowerStorage.sol";
import {
  AaveV3BorrowerImplementation as AMI,
  IERC20,
  IRewardsControllerIsh,
  IPoolAddressesProvider,
  IPool,
  ICreditDelegationToken,
  IPool,
  IPriceOracleGetter,
  DataTypes
} from "./AaveV3BorrowerImplementation.sol";

contract AaveV3Borrower is AaveV3Lender {
  /**
   * @notice address of the implementation contract
   */
  address public immutable IMPLEMENTATION;
  /**
   * @notice address of AAVE price oracle (must be the price oracle used by the pool)
   */
  /**
   * @dev price oracle and pool address can be obtained from AAVE's address provider contract
   */
  IPriceOracleGetter public immutable ORACLE;
  uint public immutable INTEREST_RATE_MODE;
  uint16 public immutable REFERRAL_CODE;

  /**
   * @notice contract's constructor
   * @param _addressesProvider address of AAVE's address provider
   * @param _referralCode code used by aave to identify certain partners, this can be safely set to 0
   * @param _interestRateMode interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
   */
  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode) AaveV3Lender(_addressesProvider) {
    REFERRAL_CODE = uint16(_referralCode);
    INTEREST_RATE_MODE = _interestRateMode;

    address _priceOracle = IPoolAddressesProvider(_addressesProvider).getAddress("PRICE_ORACLE");
    require(_priceOracle != address(0), "AaveModule/0xPriceOracle");

    ORACLE = IPriceOracleGetter(_priceOracle);
    IMPLEMENTATION = address(new AMI(POOL, IPriceOracleGetter(_priceOracle)));
  }

  /**
   * @notice convenience function to obtain the address of the non transferrable debt token overlying of some asset
   * @param asset the underlying asset
   * @param interestRateMode the interest rate (stable or variable) of the debt token
   * @return debtTkn the overlying debt token
   */
  function debtToken(IERC20 asset, uint interestRateMode) public view returns (ICreditDelegationToken debtTkn) {
    debtTkn = interestRateMode == 1
      ? ICreditDelegationToken(POOL.getReserveData(address(asset)).stableDebtTokenAddress)
      : ICreditDelegationToken(POOL.getReserveData(address(asset)).variableDebtTokenAddress);
  }

  /**
   * @notice intermediate function to allow a call to be delagated to IMPLEMENTATION while preserving the a `view` attribute.
   * @dev scheme is as follows: for some `view` function `f` of IMPLEMENTATION, one does `staticcall(_staticdelegatecall(f))` which will retain for the `view` attribute
   */
  function _staticdelegatecall(bytes calldata data) external {
    require(msg.sender == address(this), "AaveModule/internalOnly");
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(data);
    if (!success) {
      AMS.revertWithData(retdata);
    }
    assembly {
      return(add(retdata, 32), returndatasize())
    }
  }

  /**
   * @notice Returns max redeem R and borrow capacity B|R, which would occur after the redeem.
   * @param asset the underlying asset to withdraw and potentially borrow
   * @param tryBorrow also computes borrow capacity after all redeem is complete (costs extra gas).
   * @param onBehalf user for whom max redeem/borrow is computed
   * @return maxRedeemableUnderlying maximum amount `onBehalf` can redeem of `asset`
   * @return maxBorrowAfterRedeemInUnderlying max amount `onBehalf` can borrow in `asset` ater redeeming of `maxRedeemableUnderlying`.
   * @dev `maxBorrowAfterRedeemInUnderlying` is always 0 if `tryBorrow` is `false`.
   */
  function maxGettableUnderlying(IERC20 asset, bool tryBorrow, address onBehalf)
    public
    view
    returns (uint maxRedeemableUnderlying, uint maxBorrowAfterRedeemInUnderlying)
  {
    (bool success, bytes memory retdata) = address(this).staticcall(
      abi.encodeWithSelector(
        this._staticdelegatecall.selector,
        abi.encodeWithSelector(AMI.$maxGettableUnderlying.selector, asset, tryBorrow, onBehalf)
      )
    );
    if (!success) {
      AMS.revertWithData(retdata);
    } else {
      return abi.decode(retdata, (uint, uint));
    }
  }

  function getCaps(IERC20 asset) public view returns (uint supplyCap, uint borrowCap) {
    (bool success, bytes memory retdata) = address(this).staticcall(
      abi.encodeWithSelector(this._staticdelegatecall.selector, abi.encodeWithSelector(AMI.$getCaps.selector, asset))
    );
    if (!success) {
      AMS.revertWithData(retdata);
    }
    (supplyCap, borrowCap) = abi.decode(retdata, (uint, uint));
  }

  /**
   * @notice deposits assets on AAVE by first repaying debt if any and then supplying to the pool
   * @param token the asset one is depositing
   * @param onBehalf the account one is repaying and supplying for
   * @param amount of asset one is repaying and supplying
   */
  function _repayThenDeposit(IERC20 token, address onBehalf, uint amount) internal {
    // AAVE repay/deposit throws if amount == 0
    if (amount == 0) {
      return;
    }

    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(AMI.$repayThenDeposit.selector, INTEREST_RATE_MODE, REFERRAL_CODE, token, onBehalf, amount)
    );
    if (!success) {
      AMS.revertWithData(retdata);
    }
  }

  /**
   * @notice withdraws liquidity on aave, if not enough liquidity is withdrawn, tries to borrow what's missing.
   * @param token the asset that needs to be redeemed
   * @param onBehalf the account whose collateral is beeing withdrawn and borrowed upon.
   * @dev if `onBehalf != address(this)` then `this` needs to be approved by `onBehalf` using `approveDelegation` of the overlying debt token
   * @param amount the target amount of `token` one needs to redeem
   * @param strict whether call allows contract to redeem more than amount (for gas optimization).
   * @dev function will only try to borrow if less than `amount` was redeemed and will not try to borrow more than what is missing, even if `strict` is not required.
   * @dev this is forced by aave v3 currently not allowing to repay a debt that was incurred on the same block (so no gas optim can be used). Repaying on the next block would be dangerous as `onBehalf` position could possibly be liquidated
   * @param recipient the target address to which redeemed and borrowed tokens should be sent
   * @return got how much asset was transfered to caller
   */
  function _redeemThenBorrow(IERC20 token, address onBehalf, uint amount, bool strict, address recipient)
    internal
    returns (uint got)
  {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$redeemThenBorrow.selector, INTEREST_RATE_MODE, REFERRAL_CODE, token, onBehalf, amount, strict, recipient
      )
    );
    if (success) {
      got = abi.decode(retdata, (uint));
    } else {
      AMS.revertWithData(retdata);
    }
  }

  ///@notice tries to borrow some assets from the pool
  ///@param token the asset one is borrowing
  ///@param onBehalf the account whose collateral is being used to borrow (caller must be approved by `onBehalf` -if different- using `approveDelegation` from the corresponding debt token (variable or stable))
  function _borrow(IERC20 token, uint amount, address onBehalf) internal {
    POOL.borrow(address(token), amount, INTEREST_RATE_MODE, REFERRAL_CODE, onBehalf);
  }

  ///@notice repays debt to the pool
  ///@param token the asset one is repaying
  ///@param amount of assets one is repaying
  ///@param onBehalf account whose debt is being repaid
  function _repay(IERC20 token, uint amount, address onBehalf) internal returns (uint repaid) {
    repaid = (amount == 0) ? 0 : POOL.repay(address(token), amount, INTEREST_RATE_MODE, onBehalf);
  }

  ///@notice returns the debt of a user
  ///@param underlying the asset whose debt balance is being viewed
  ///@param account the account whose debt balance is being viewed
  ///@return debt the amount of tokens (in units of `underlying`) that should be repaid to the pool
  ///@dev user can only borrow underlying in variable or stable, not both
  function borrowed(address underlying, address account) public view returns (uint debt) {
    DataTypes.ReserveData memory rd = POOL.getReserveData(underlying);
    return INTEREST_RATE_MODE == 1
      ? IERC20(rd.stableDebtTokenAddress).balanceOf(account)
      : IERC20(rd.variableDebtTokenAddress).balanceOf(account);
  }
}
