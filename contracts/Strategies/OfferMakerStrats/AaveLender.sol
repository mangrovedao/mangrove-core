// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/Aave/ILendingPool.sol";
import "../interfaces/Aave/ILendingPoolAddressesProvider.sol";
import "../interfaces/Aave/IPriceOracleGetter.sol";

import "hardhat/console.sol";

abstract contract AaveLender is MangroveOffer {
  event ErrorOnRedeem(address ctoken, uint amount);
  event ErrorOnMint(address ctoken, uint amount);

  // address of the lendingPool
  ILendingPool public immutable lendingPool;
  IPriceOracleGetter public immutable priceOracle;
  uint16 referralCode;

  constructor(address _addressesProvider, uint _referralCode) {
    require(
      uint16(_referralCode) == _referralCode,
      "Referral code should be uint16"
    );
    referralCode = uint16(referralCode); // for aave reference, put 0 for tests
    address _lendingPool = ILendingPoolAddressesProvider(_addressesProvider)
      .getLendingPool();
    address _priceOracle = ILendingPoolAddressesProvider(_addressesProvider)
      .getPriceOracle();
    require(_lendingPool != address(0), "Invalid lendingPool address");
    require(_priceOracle != address(0), "Invalid priceOracle address");
    lendingPool = ILendingPool(_lendingPool);
    priceOracle = IPriceOracleGetter(_priceOracle);
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval of ctoken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function approveLender(IERC20 token, uint amount) external onlyAdmin {
    token.approve(address(lendingPool), amount);
  }

  function mint(IERC20 underlying, uint amount) external onlyAdmin {
    aaveMint(underlying, amount);
  }

  function redeem(IERC20 underlying, uint amount) external onlyAdmin {
    aaveRedeem(underlying, amount);
  }

  ///@notice exits markets
  function exitMarket(IERC20 underlying) external onlyAdmin {
    lendingPool.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function enterMarkets(IERC20[] calldata underlyings) external onlyAdmin {
    for (uint i = 0; i < underlyings.length; i++) {
      lendingPool.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
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

  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)

  function maxGettableUnderlying(IERC20 asset)
    public
    view
    returns (uint, uint)
  {
    Underlying memory underlying; // asset parameters
    Account memory account; // accound parameters
    (
      account.collateral,
      account.debt,
      account.borrowPower, // avgLtv * sumCollateralEth - sumDebtEth
      account.liquidationThreshold,
      account.ltv,
      account.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
    ) = lendingPool.getUserAccountData(address(this));
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
      address(asset)
    );
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      ,
      /*liquidationBonus*/
      underlying.decimals,
      /*reserveFactor*/

    ) = DataTypes.getParams(reserveData.configuration);
    account.balanceOfUnderlying = IERC20(reserveData.aTokenAddress).balanceOf(
      address(this)
    );

    underlying.price = priceOracle.getAssetPrice(address(asset)); // divided by 10**underlying.decimals

    // account.redeemPower = account.liquidationThreshold * account.collateral - account.debt
    account.redeemPower = sub_(
      div_(mul_(account.liquidationThreshold, account.collateral), 10**4),
      account.debt
    );
    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())

    uint maxRedeemableUnderlying = div_( // in 10**underlying.decimals
      account.redeemPower * 10**(underlying.decimals) * 10**4,
      mul_(underlying.liquidationThreshold, underlying.price)
    );

    maxRedeemableUnderlying = min(
      maxRedeemableUnderlying,
      account.balanceOfUnderlying
    );
    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = div_(
      mul_(maxRedeemableUnderlying, underlying.ltv),
      10**4
    );
    uint borrowPowerInUnderlying = div_(
      mul_(account.borrowPower, 10**underlying.decimals),
      underlying.price
    );

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    uint maxBorrowAfterRedeemInUnderlying = sub_( // max borrow power in underlying after max redeem has been withdrawn
      borrowPowerInUnderlying,
      borrowPowerImpactOfRedeemInUnderlying
    );
    return (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying);
  }

  ///@notice method to get `outbound_tkn` during makerExecute
  ///@param outbound_tkn address of the ERC20 managing `outbound_tkn` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    (
      uint redeemable, /*maxBorrowAfterRedeem*/

    ) = maxGettableUnderlying(outbound_tkn);

    uint redeemAmount = min(redeemable, amount);

    if (aaveRedeem(outbound_tkn, redeemAmount) == 0) {
      // redeemAmount was transfered to `this`
      return (amount - redeemAmount);
    }
    return amount;
  }

  function aaveRedeem(IERC20 asset, uint amountToRedeem)
    internal
    returns (uint)
  {
    try
      lendingPool.withdraw(address(asset), amountToRedeem, address(this))
    returns (uint withdrawn) {
      //aave redeem was a success
      if (amountToRedeem == withdrawn) {
        return 0;
      } else {
        emit ErrorOnRedeem(address(asset), amountToRedeem);
        return (amountToRedeem - withdrawn);
      }
    } catch {
      //compound redeem failed
      emit ErrorOnRedeem(address(asset), amountToRedeem);
      return amountToRedeem;
    }
  }

  function __put__(IERC20 inbound_tkn, uint amount) internal virtual override {
    //optim
    if (amount == 0) {
      return;
    }
    aaveMint(inbound_tkn, amount);
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `ctoken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve ctoken in order to mint
  function aaveMint(IERC20 inbound_tkn, uint amount) internal {
    // contract must haveallowance()to spend funds on behalf ofmsg.sender for at-leastamount for the asset being deposited. This can be done via the standard ERC20 approve() method.
    try
      lendingPool.deposit(
        address(inbound_tkn),
        amount,
        address(this),
        referralCode
      )
    {
      return;
    } catch {
      emit ErrorOnMint(address(inbound_tkn), amount);
    }
  }
}
