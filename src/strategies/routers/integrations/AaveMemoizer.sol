// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {AaveV3Borrower, DataTypes} from "mgv_src/strategies/integrations/AaveV3Borrower.sol";
import {ReserveConfiguration} from "mgv_src/strategies/vendor/aave/v3/ReserveConfiguration.sol";
import {ICreditDelegationToken} from "mgv_src/strategies/vendor/aave/v3/ICreditDelegationToken.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow.
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
contract AaveMemoizer is AaveV3Borrower {
  ///@param balanceOf the owner's balance of the token
  ///@param balanceOfMemoized whether the `balanceOf` has been memoized.
  ///@param overlyingBalanceOf the balance of the overlying.
  ///@param overlyingBalanceOfMemoized whether the `overlyingBalanceOf` has been memoized.
  ///@param reserveData the data pertaining to the asset
  ///@param reserveDataMemoized whether the `reserveData` has been memoized.
  ///@param debtBalanceOf amount of token borrowed by this contract
  ///@param debtBalanceOfMemoized wether `debtBalanceOf` is memoized

  struct Account {
    uint collateral;
    uint debt;
    uint borrowPower;
    uint ltv;
    uint liquidationThreshold;
    uint health;
  }

  struct Memoizer {
    uint balanceOf;
    bool balanceOfMemoized;
    uint overlyingBalanceOf;
    bool overlyingBalanceOfMemoized;
    DataTypes.ReserveData reserveData;
    bool reserveDataMemoized;
    uint debtBalanceOf;
    bool debtBalanceOfMemoized;
    Account userAccountData;
    bool userAccountDataMemoized;
    uint assetPrice;
    bool assetPriceMemoized;
  }

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode) AaveV3Borrower(addressesProvider, interestRateMode) {}

  function reserveData(IERC20 token, Memoizer memory m) internal view returns (DataTypes.ReserveData memory) {
    if (!m.reserveDataMemoized) {
      m.reserveDataMemoized = true;
      m.reserveData = POOL.getReserveData(address(token));
    }
    return m.reserveData;
  }

  ///@notice Gets the overlying for the token.
  ///@param token the token.
  ///@param m the memoizer
  ///@return overlying for the token.
  function overlying(IERC20 token, Memoizer memory m) internal view returns (IERC20) {
    return IERC20(reserveData(token, m).aTokenAddress);
  }

  ///@notice Gets the balance for the overlying of the token
  ///@param token the token.
  ///@param m the memoizer
  function overlyingBalanceOf(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.overlyingBalanceOfMemoized) {
      m.overlyingBalanceOfMemoized = true;
      IERC20 aToken = overlying(token, m);
      if (aToken == IERC20(address(0))) {
        m.overlyingBalanceOf = 0;
      } else {
        m.overlyingBalanceOf = aToken.balanceOf(address(this));
      }
    }
    return m.overlyingBalanceOf;
  }

  ///@notice Gets the token balance of `this`
  ///@param token the token.
  ///@param m the memoizer
  function balanceOf(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.balanceOfMemoized) {
      m.balanceOfMemoized = true;
      m.balanceOf = token.balanceOf(address(this));
    }
    return m.balanceOf;
  }

  /**
   * @notice convenience function to obtain the address of the non transferrable debt token overlying of some asset
   * @param token the underlying asset
   * @return debtTkn the overlying debt token
   */
  function debtToken(IERC20 token, Memoizer memory m) public view returns (ICreditDelegationToken debtTkn) {
    debtTkn = INTEREST_RATE_MODE == 1
      ? ICreditDelegationToken(reserveData(token, m).stableDebtTokenAddress)
      : ICreditDelegationToken(reserveData(token, m).variableDebtTokenAddress);
  }

  ///@notice returns the debt of `this`
  ///@param token the asset whose debt balance is being viewed
  ///@dev user can only borrow underlying in variable or stable, not both
  function debtBalanceOf(IERC20 token, Memoizer memory m) public view returns (uint) {
    if (!m.debtBalanceOfMemoized) {
      m.debtBalanceOfMemoized = true;
      m.debtBalanceOf = debtToken(token, m).balanceOf(address(this));
    }
    return m.debtBalanceOf;
  }

  function supplyCap(IERC20 token, Memoizer memory m) public view returns (uint) {
    return ReserveConfiguration.getSupplyCap(reserveData(token, m).configuration);
  }

  function borrowCap(IERC20 token, Memoizer memory m) public view returns (uint) {
    return ReserveConfiguration.getBorrowCap(reserveData(token, m).configuration);
  }

  function userAccountData(Memoizer memory m) public view returns (Account memory) {
    if (!m.userAccountDataMemoized) {
      m.userAccountDataMemoized = true;
      (
        m.userAccountData.collateral,
        m.userAccountData.debt,
        m.userAccountData.borrowPower, // avgLtv * sumCollateralEth - sumDebtEth
        m.userAccountData.liquidationThreshold,
        m.userAccountData.ltv,
        m.userAccountData.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
      ) = POOL.getUserAccountData(address(this));
    }
    return m.userAccountData;
  }

  function assetPrice(IERC20 token, Memoizer memory m) public view returns (uint) {
    if (!m.assetPriceMemoized) {
      m.assetPriceMemoized = true;
      m.assetPrice = ORACLE.getAssetPrice(address(token));
    }
    return m.assetPrice;
  }
}
