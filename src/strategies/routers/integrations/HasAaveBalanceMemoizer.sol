// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {AaveV3Lender} from "mgv_src/strategies/integrations/AaveV3Lender.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow.
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
contract HasAaveBalanceMemoizer is AaveV3Lender {
  ///@param balanceOf the owner's balance of the token
  ///@param balanceOfMemoized whether the `balanceOf` has been memoized.
  ///@param balanceOfOverlying the balance of the overlying.
  ///@param balanceOfOverlyingMemoized whether the `balanceOfOverlying` has been memoized.
  ///@param overlying the overlying
  ///@param overlyingMemoized whether the `overlying` has been memoized.
  struct BalanceMemoizer {
    uint balanceOf;
    bool balanceOfMemoized;
    uint balanceOfOverlying;
    bool balanceOfOverlyingMemoized;
    IERC20 overlying;
    bool overlyingMemoized;
  }

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  constructor(address addressesProvider) AaveV3Lender(addressesProvider) {}

  ///@notice Gets the overlying for the token.
  ///@param token the token.
  ///@param memoizer the memoizer.
  ///@return overlying for the token.
  function overlying(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (IERC20) {
    if (memoizer.overlyingMemoized) {
      return memoizer.overlying;
    } else {
      memoizer.overlyingMemoized = true;
      memoizer.overlying = overlying(token);
      return memoizer.overlying;
    }
  }

  ///@notice Gets the balance for the overlying of the token, or 0 if there is no overlying.
  ///@param token the token.
  ///@param memoizer the memoizer.
  ///@return balance of the overlying, or 0 if there is no overlying.
  function balanceOfOverlying(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (memoizer.balanceOfOverlyingMemoized) {
      return memoizer.balanceOfOverlying;
    } else {
      memoizer.balanceOfOverlyingMemoized = true;
      IERC20 aToken = overlying(token, memoizer);
      if (aToken == IERC20(address(0))) {
        memoizer.balanceOfOverlying = 0;
      } else {
        memoizer.balanceOfOverlying = aToken.balanceOf(address(this));
      }
      return memoizer.balanceOfOverlying;
    }
  }

  ///@notice Gets the balance of the token
  ///@param token the token.
  ///@param memoizer the memoizer.
  ///@return balance of the token.
  function balanceOf(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (memoizer.balanceOfMemoized) {
      return memoizer.balanceOf;
    } else {
      memoizer.balanceOfMemoized = true;
      memoizer.balanceOf = token.balanceOf(address(this));
      return memoizer.balanceOf;
    }
  }
}
