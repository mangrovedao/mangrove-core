// SPDX-License-Identifier:	BSD-2-Clause

//AaveModuleImplementation.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import {AaveV3ModuleStorage as AMS, IRewardsControllerIsh, IPoolAddressesProvider, ICreditDelegationToken, IPool, IPriceOracleGetter, DataTypes, RC} from "./AaveModuleStorage.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import "mgv_src/strategies/utils/TransferLib.sol";

contract AaveV3ModuleImplementation {
  IPool public immutable POOL;
  IPriceOracleGetter public immutable ORACLE;

  constructor(IPool pool, IPriceOracleGetter oracle) {
    POOL = pool;
    ORACLE = oracle;
  }

  // structs to avoir stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  struct Account {
    uint collateral;
    uint debt;
    uint borrowPower;
    uint redeemPower;
    uint ltv;
    uint liquidationThreshold;
    uint health;
    uint balanceOfUnderlying;
  }

  function $maxGettableUnderlying(
    address asset,
    bool tryBorrow,
    address onBehalf
  ) public view returns (uint, uint) {
    Underlying memory underlying; // asset parameters
    Account memory account; // accound parameters
    (
      account.collateral,
      account.debt,
      account.borrowPower, // avgLtv * sumCollateralEth - sumDebtEth
      account.liquidationThreshold,
      account.ltv,
      account.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
    ) = POOL.getUserAccountData(onBehalf);
    DataTypes.ReserveData memory reserveData = POOL.getReserveData(asset);
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      ,
      /*liquidationBonus*/
      underlying.decimals,
      /*reserveFactor*/
      /*emode_category*/
      ,

    ) = RC.getParams(reserveData.configuration);
    account.balanceOfUnderlying = IERC20(reserveData.aTokenAddress).balanceOf(
      onBehalf
    );

    underlying.price = ORACLE.getAssetPrice(asset); // divided by 10**underlying.decimals

    // account.redeemPower = account.liquidationThreshold * account.collateral - account.debt
    account.redeemPower =
      (account.liquidationThreshold * account.collateral) /
      10**4 -
      account.debt;
    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())

    uint maxRedeemableUnderlying = (account.redeemPower * // in 10**underlying.decimals
      10**(underlying.decimals) *
      10**4) / (underlying.liquidationThreshold * underlying.price);

    maxRedeemableUnderlying = (maxRedeemableUnderlying <
      account.balanceOfUnderlying)
      ? maxRedeemableUnderlying
      : account.balanceOfUnderlying;

    if (!tryBorrow) {
      //gas saver
      return (maxRedeemableUnderlying, 0);
    }
    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = (maxRedeemableUnderlying *
      underlying.ltv) / 10**4;

    uint borrowPowerInUnderlying = (account.borrowPower *
      10**underlying.decimals) / underlying.price;

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    // max borrow power in underlying after max redeem has been withdrawn
    uint maxBorrowAfterRedeemInUnderlying = borrowPowerInUnderlying -
      borrowPowerImpactOfRedeemInUnderlying;

    return (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying);
  }

  function $repayThenDeposit(
    uint interestRateMode,
    uint referralCode,
    IERC20 token,
    address onBehalf,
    uint amount
  ) external {
    // AAVE repay/deposit throws if amount == 0
    if (amount == 0) {
      return;
    }
    uint toMint = amount;
    try
      // there are several reasons a repay may fail:
      // * trying to repay more than debt is OK provided debt is not 0 (AAVE throws is debt is 0)
      // * repaying maxUint will not work when repaying on behalf !
      // * cannot repay a borrow that has the same block stamp
      POOL.repay(address(token), amount, interestRateMode, onBehalf)
    returns (uint repaid) {
      toMint -= repaid;
      if (toMint == 0) {
        return;
      }
    } catch {
      /** Recovering from one of the above 3 cases */
    }
    POOL.supply(address(token), toMint, onBehalf, uint16(referralCode));
  }

  function $redeemThenBorrow(
    uint interestRateMode,
    uint referralCode,
    IERC20 token,
    address onBehalfOf,
    uint amount,
    bool strict,
    address recipient
  ) external returns (uint) {
    (uint redeemable, uint borrowable_after_redeem) = $maxGettableUnderlying(
      address(token),
      true, // compute borrow power after redeem
      onBehalfOf
    );
    if (strict) {
      redeemable = (redeemable < amount) ? redeemable : amount;
    }
    // `this` contract must have the aToken to withdraw on AAVE
    // there is no `withdraw` on behalf as of July 2022
    require(
      TransferLib.transferTokenFrom(
        IERC20(POOL.getReserveData(address(token)).aTokenAddress),
        onBehalfOf,
        address(this),
        redeemable
      ),
      "AaveModule/redeemThenBorrow/aTknTransferFail"
    );
    // redeemed tokens are direclty transfered to `recipient`
    if (redeemable > 0) {
      POOL.withdraw(address(token), redeemable, recipient);
    }

    if (redeemable >= amount || borrowable_after_redeem == 0) {
      return redeemable;
    } else {
      amount -= redeemable;
      // still missing liquidity to reach target amount
      borrowable_after_redeem = borrowable_after_redeem > amount
        ? amount
        : borrowable_after_redeem;
      POOL.borrow(
        address(token),
        borrowable_after_redeem,
        interestRateMode,
        uint16(referralCode),
        onBehalfOf
      );
      // sending borrowed tokens to `recipient`
      require(
        TransferLib.transferToken(token, recipient, borrowable_after_redeem),
        "AaveModule/redeemThenBorrow/TknTransferFail"
      );
      return redeemable + borrowable_after_redeem;
    }
  }
}
