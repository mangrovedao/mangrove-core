// SPDX-License-Identifier:	BSD-2-Clause

//SimpleRouter.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AbstractRouter} from "./AbstractRouter.sol";

///@notice `SimpleRouter` instances pull (push) liquidity directly from (to) the reserve
///@dev Maker contracts using this router must make sure that the reserve approves the router for all asset that will be pulled (outbound tokens)
/// Thus a maker contract using a vault that is not an EOA must make sure this vault has approval capacities.
contract SimpleRouter is
  AbstractRouter(70_000) // fails for < 70K with Direct strat
{
  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @param token Token to be transferred
  /// @param reserve The address of the reserve, where the tokens will be transferred from
  /// @param maker Address of the maker, where the tokens will be transferred to
  /// @param amount The amount of tokens to be transferred
  /// @param strict wether the caller maker contract wishes to pull at most `amount`.
  /// @return pulled The amount pulled if successful (will be equal to `amount`); otherwise, 0.
  /// @dev requires approval from `reserve` for `this` to transfer `token`.
  function __pull__(IERC20 token, address reserve, address maker, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint pulled)
  {
    // if not strict, pulling all available tokens from reserve
    amount = strict ? amount : token.balanceOf(reserve);
    if (TransferLib.transferTokenFrom(token, reserve, maker, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  /// @notice router-dependent implementation of the `push` function
  /// @notice transfers an amount of tokens from the maker to the reserve.
  /// @param token Token to be transferred
  /// @param reserve The address of the reserve, where the tokens will be transferred to
  /// @param maker Address of the maker, where the tokens will be transferred from
  /// @param amount The amount of tokens to be transferred
  /// @dev requires approval from `maker` for `this` to transfer `token`.
  /// @dev will revert if transfer fails
  function __push__(IERC20 token, address reserve, address maker, uint amount) internal virtual override returns (uint) {
    bool success = TransferLib.transferTokenFrom(token, maker, reserve, amount);
    return success ? amount : 0;
  }

  ///@inheritdoc AbstractRouter
  function reserveBalance(IERC20 token, address reserve) external view override returns (uint) {
    return token.balanceOf(reserve);
  }

  ///@notice router-dependent implementation of the `checkList` function
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset whose approval must be checked
  ///@param reserve the reserve that requires asset pulling/pushing
  function __checkList__(IERC20 token, address reserve) internal view virtual override {
    // verifying that `this` router can withdraw tokens from reserve (required for `withdrawToken` and `pull`)
    require(
      reserve == address(this) || token.allowance(reserve, address(this)) > 0, "SimpleRouter/NotApprovedByReserve"
    );
  }
}
