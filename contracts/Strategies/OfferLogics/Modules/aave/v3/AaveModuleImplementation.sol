// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./AaveModuleStorage.sol";
import "hardhat/console.sol";

contract AaveV3ModuleImplementation is
  AaveV3ModuleStorage(false, address(42), 0)
{
  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)

  function maxGettableUnderlying(
    address asset,
    bool tryBorrow,
    address onBehalf
  ) public view returns (uint, uint) {
    console.log(address(lendingPool));
    console.log(address(priceOracle));
    Underlying memory underlying; // asset parameters
    Account memory account; // accound parameters
    (
      account.collateral,
      account.debt,
      account.borrowPower, // avgLtv * sumCollateralEth - sumDebtEth
      account.liquidationThreshold,
      account.ltv,
      account.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
    ) = lendingPool.getUserAccountData(onBehalf);
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
      asset
    );
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
    account.balanceOfUnderlying = IEIP20(reserveData.aTokenAddress).balanceOf(
      onBehalf
    );

    underlying.price = priceOracle.getAssetPrice(asset); // divided by 10**underlying.decimals

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

  function repayThenDeposit(
    uint interestRateMode,
    IEIP20 token,
    uint amount
  ) external {
    uint debtOfUnderlying;
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
      address(token)
    );
    if (interestRateMode == 1) {
      debtOfUnderlying = IEIP20(reserveData.stableDebtTokenAddress).balanceOf(
        address(this)
      );
    } else {
      debtOfUnderlying = IEIP20(reserveData.variableDebtTokenAddress).balanceOf(
          address(this)
        );
    }
    uint toMint;
    if (debtOfUnderlying == 0) {
      toMint = amount;
    } else {
      uint repaid = lendingPool.repay(
        address(token),
        amount,
        interestRateMode,
        address(this)
      );
      toMint = amount - repaid;
    }
    lendingPool.supply(address(token), toMint, address(this), referralCode);
  }

  function exactRedeemThenBorrow(
    uint interestRateMode,
    IEIP20 token,
    address to,
    uint amount
  ) external returns (uint) {
    (uint redeemable, uint liquidity_after_redeem) = maxGettableUnderlying(
      address(token),
      true, // compute borrow power after redeem
      address(this) // assuming aTokens are on `this` contract's balance
    );

    if (redeemable + liquidity_after_redeem < amount) {
      return amount; // give up early if not possible to fetch amount of underlying
    }
    // 2. trying to redeem liquidity from Compound
    uint toRedeem = (redeemable < amount) ? redeemable : amount;

    uint redeemed = lendingPool.withdraw(address(token), toRedeem, to);
    // `toRedeem` was computed such that lender should allow this contract to withdraw all of it
    // if this should fail it must be because the lender is running out of cash
    require(redeemed == toRedeem, "AaveModule/lenderOutOfCash");

    amount = amount - toRedeem;

    if (amount == 0) {
      return 0;
    }
    // 3. trying to borrow missing liquidity
    // NB `to` must have approved `this` contract for delegation unless `to == address(this)`
    lendingPool.borrow(
      address(token),
      amount,
      interestRateMode,
      referralCode,
      to
    );
    return 0;
  }

  function _borrow(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address to
  ) internal {
    lendingPool.borrow(
      address(token),
      amount,
      interestRateMode,
      referralCode,
      to
    );
  }

  function _redeem(
    IEIP20 token,
    uint amount,
    address to
  ) internal returns (uint redeemed) {
    redeemed = lendingPool.withdraw(address(token), amount, to);
  }

  function _mint(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) internal {
    lendingPool.supply(address(token), amount, onBehalf, referralCode);
  }

  function _repay(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address onBehalf
  ) internal returns (uint repaid) {
    return
      lendingPool.repay(address(token), amount, interestRateMode, onBehalf);
  }

  // rewards claiming.
  // may use `SingleUser.redeemToken` to move collected tokens afterwards
  function _claimRewards(
    IRewardsControllerIsh rewardsController,
    address[] calldata assets
  )
    internal
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    (rewardsList, claimedAmounts) = rewardsController.claimAllRewardsToSelf(
      assets
    );
  }
}
