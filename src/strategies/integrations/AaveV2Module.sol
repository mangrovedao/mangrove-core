// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import "mgv_src/strategies/vendor/aave/v2/ILendingPool.sol";
import "mgv_src/strategies/vendor/aave/v2/ILendingPoolAddressesProvider.sol";
import "mgv_src/strategies/vendor/aave/v2/IPriceOracleGetter.sol";
import "mgv_src/strategies/vendor/compound/Exponential.sol";
import "mgv_src/IMangrove.sol";
import {IERC20, MgvLib} from "mgv_src/MgvLib.sol";

contract AaveModule is Exponential {
  event ErrorOnRedeem(
    address indexed outbound_tkn, address indexed inbound_tkn, uint indexed offerId, uint amount, string errorCode
  );
  event ErrorOnMint(
    address indexed outbound_tkn, address indexed inbound_tkn, uint indexed offerId, uint amount, string errorCode
  );

  // address of the lendingPool
  ILendingPool public immutable lendingPool;
  IPriceOracleGetter public immutable priceOracle;
  uint16 referralCode;

  constructor(address _addressesProvider, uint _referralCode) {
    require(uint16(_referralCode) == _referralCode, "Referral code should be uint16");
    referralCode = uint16(referralCode); // for aave reference, put 0 for tests
    address _lendingPool = ILendingPoolAddressesProvider(_addressesProvider).getLendingPool();
    address _priceOracle = ILendingPoolAddressesProvider(_addressesProvider).getPriceOracle();
    require(_lendingPool != address(0), "Invalid lendingPool address");
    require(_priceOracle != address(0), "Invalid priceOracle address");
    lendingPool = ILendingPool(_lendingPool);
    priceOracle = IPriceOracleGetter(_priceOracle);
  }

  /**
   *
   */
  ///@notice Required functions to let `this` contract interact with Aave
  /**
   *
   */

  ///@notice approval of overlying contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function _approveLender(IERC20 token, uint amount) internal {
    token.approve(address(lendingPool), amount);
  }

  ///@notice exits markets
  function _exitMarket(IERC20 underlying) internal {
    lendingPool.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function _enterMarkets(IERC20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; i++) {
      lendingPool.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = IERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);
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

  function maxGettableUnderlying(IERC20 asset, bool tryBorrow, address onBehalf) public view returns (uint, uint) {
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
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(address(asset));
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      ,
      /*liquidationBonus*/
      underlying.decimals,
      /*reserveFactor*/
    ) = DataTypes.getParams(reserveData.configuration);
    account.balanceOfUnderlying = IERC20(reserveData.aTokenAddress).balanceOf(onBehalf);

    underlying.price = priceOracle.getAssetPrice(address(asset)); // divided by 10**underlying.decimals

    // account.redeemPower = account.liquidationThreshold * account.collateral - account.debt
    account.redeemPower = sub_(div_(mul_(account.liquidationThreshold, account.collateral), 10 ** 4), account.debt);
    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())

    uint maxRedeemableUnderlying = div_( // in 10**underlying.decimals
      account.redeemPower * 10 ** (underlying.decimals) * 10 ** 4,
      mul_(underlying.liquidationThreshold, underlying.price)
    );

    maxRedeemableUnderlying = min(maxRedeemableUnderlying, account.balanceOfUnderlying);

    if (!tryBorrow) {
      //gas saver
      return (maxRedeemableUnderlying, 0);
    }
    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = div_(mul_(maxRedeemableUnderlying, underlying.ltv), 10 ** 4);
    uint borrowPowerInUnderlying = div_(mul_(account.borrowPower, 10 ** underlying.decimals), underlying.price);

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    uint maxBorrowAfterRedeemInUnderlying = sub_( // max borrow power in underlying after max redeem has been withdrawn
    borrowPowerInUnderlying, borrowPowerImpactOfRedeemInUnderlying);
    return (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying);
  }

  function aaveRedeem(uint amountToRedeem, address onBehalf, MgvLib.SingleOrder calldata order) internal returns (uint) {
    try lendingPool.withdraw(order.outbound_tkn, amountToRedeem, onBehalf) returns (uint withdrawn) {
      //aave redeem was a success
      if (amountToRedeem == withdrawn) {
        return 0;
      } else {
        return (amountToRedeem - withdrawn);
      }
    } catch Error(string memory message) {
      emit ErrorOnRedeem(order.outbound_tkn, order.inbound_tkn, order.offerId, amountToRedeem, message);
      return amountToRedeem;
    }
  }

  function _supply(uint amount, address token, address onBehalf) internal {
    lendingPool.deposit(token, amount, onBehalf, referralCode);
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `ctoken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve ctoken in order to mint
  function aaveMint(uint amount, address onBehalf, MgvLib.SingleOrder calldata order) internal returns (uint) {
    // contract must haveallowance()to spend funds on behalf ofmsg.sender for at-leastamount for the asset being deposited. This can be done via the standard ERC20 approve() method.
    try lendingPool.deposit(order.inbound_tkn, amount, onBehalf, referralCode) {
      return 0;
    } catch Error(string memory message) {
      emit ErrorOnMint(order.outbound_tkn, order.inbound_tkn, order.offerId, amount, message);
    } catch {
      emit ErrorOnMint(order.outbound_tkn, order.inbound_tkn, order.offerId, amount, "unexpected");
    }
    return amount;
  }
}
