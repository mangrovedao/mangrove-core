// SPDX-License-Identifier:	BSD-2-Clause

// TetuLender.sol

// Copyright (c) 2023 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {ISmartVault} from "../vendor/tetu/ISmartVault.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

import {console} from "forge-std/console.sol";

/// @title This contract provides a collection of lending capabilities with AAVE-v3 to whichever contract inherits it
contract TetuLender {
  ///@notice The AAVE pool retrieved from the pool provider.
  ISmartVault public immutable VAULT;
  IERC20 public immutable OVERLYING;
  IERC20 public immutable UNDERLYING;

  /// @notice contract's constructor
  /// @param vault address of the smart vault
  constructor(address vault) {
    console.log("building tetu lender");
    VAULT = ISmartVault(vault);
    OVERLYING = IERC20(vault);
    UNDERLYING = IERC20(ISmartVault(vault).underlying());
  }

  /// @notice allows this contract to approve the VAULT to transfer some underlying asset on its behalf
  /// @dev this is a necessary step prior to supplying tokens to the VAULT
  /// @param token the underlying asset for which approval is required
  /// @param amount the approval amount
  function _approveLender(IERC20 token, uint amount) internal {
    TransferLib.approveToken(token, address(VAULT), amount);
  }

  ///@notice redeems funds from the vault
  ///@param amount of assets one wishes to redeem
  ///@param to is the address where the redeemed assets should be transferred
  ///@return redeemed the amount of asset that were transferred to `to`
  function _redeem(uint amount, address to) internal returns (uint redeemed) {
    try VAULT.withdraw(amount) {
      if (TransferLib.transferToken(UNDERLYING, to, amount)) {
        return amount;
      }
    } catch {}
    return 0;
  }

  ///@notice supplies funds to the vault
  ///@param amount of assets to be transferred to the pool
  ///@param onBehalf address of the account whose collateral is being supplied to and which will receive the overlying
  ///@param noRevert does not revert if supplies throws
  ///@return reason for revert from Aave.
  function _supply(uint amount, address onBehalf, bool noRevert) internal returns (bytes32) {
    if (amount == 0) {
      return bytes32(0);
    } else {
      try VAULT.depositFor(amount, onBehalf) {
        return bytes32(0);
      } catch Error(string memory reason) {
        require(noRevert, reason);
        return bytes32(bytes(reason));
      } catch {
        require(noRevert, "noReason");
        return "noReason";
      }
    }
  }

  function _supplyAndInvest(uint amount, bool noRevert) internal returns (bytes32) {
    try VAULT.depositAndInvest(amount) {
      return bytes32(0);
    } catch Error(string memory reason) {
      require(noRevert, reason);
      return bytes32(bytes(reason));
    } catch {
      require(noRevert, "noReason");
      return "noReason";
    }
  }

  ///@notice rewards claiming.
  ///@param to whom the rewards should be sent
  function _claimRewards(address to) internal {
    VAULT.getAllRewardsAndRedirect(to);
  }
}
