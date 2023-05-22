// SPDX-License-Identifier:	BSD-2-Clause

// TetuLender.sol

// Copyright (c) 2023 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {IVault} from "../vendor/beefy/IVault.sol";
import {IStrategyComplete} from "../vendor/beefy/IStrategyComplete.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

/// @title This contract provides basic interaction capabilities with Beefy vaults
contract BeefyLender {
  ///@notice The AAVE pool retrieved from the pool provider.
  IVault public immutable VAULT;
  IERC20 public immutable OVERLYING;
  IERC20 public immutable UNDERLYING;
  IStrategyComplete public immutable STRATEGY;

  /// @notice contract's constructor
  /// @param vault address of the smart vault
  constructor(address vault) {
    VAULT = IVault(vault);
    OVERLYING = IERC20(vault);
    UNDERLYING = IERC20(IVault(vault).want());
    STRATEGY = IStrategyComplete(IVault(vault).strategy());
  }

  /// @notice allows this contract to approve the VAULT to transfer some underlying asset on its behalf
  /// @dev this is a necessary step prior to supplying tokens to the VAULT
  /// @param amount the approval amount
  function _approveLender(uint amount) internal {
    TransferLib.approveToken(UNDERLYING, address(VAULT), amount);
  }

  ///@notice redeems funds from the vault
  ///@param amount of underlying one wishes to redeem, use max uint to withdraw all shares
  ///@return redeemed the amount of asset that were redeemed from the vault
  function _redeem(uint amount) internal returns (uint redeemed) {
    uint balBefore = UNDERLYING.balanceOf(address(this));
    if (amount == type(uint).max) {
      VAULT.withdrawAll();
    } else {
      uint sharesToRedeem = amount * 10 ** (18 - UNDERLYING.decimals()) / VAULT.getPricePerFullShare();
      VAULT.withdraw(sharesToRedeem);
    }
    return UNDERLYING.balanceOf(address(this)) - balBefore;
  }

  ///@notice supplies funds to the vault
  ///@param amount of assets to be transferred to the pool
  ///@param noRevert does not revert if supplies throws
  ///@return reason for revert from Vault.
  function _supply(uint amount, bool noRevert) internal returns (bytes32) {
    if (amount == 0) {
      return bytes32(0);
    } else {
      // this transfers amount tokens to the vault, which invests immediately
      try VAULT.deposit(amount) {
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
}
