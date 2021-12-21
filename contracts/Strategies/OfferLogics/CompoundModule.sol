// SPDX-License-Identifier:	BSD-2-Clause

// CompoundModule.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../interfaces/compound/ICompound.sol";
import "../lib/Exponential.sol";
import {MgvLib as ML} from "../../MgvLib.sol";

//import "hardhat/console.sol";

contract CompoundModule is Exponential {
  event ErrorOnRedeem(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    uint amount,
    uint errorCode
  );
  event ErrorOnMint(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    uint amount,
    uint errorCode
  );

  event ComptrollerError(address comp, uint errorCode);

  // mapping : ERC20 -> cERC20
  mapping(IERC20 => IcERC20) overlyings;

  // address of the comptroller
  IComptroller public immutable comptroller;

  // address of the price oracle used by the comptroller
  ICompoundPriceOracle public immutable oracle;

  IERC20 immutable weth;

  constructor(address _unitroller, address wethAddress) {
    comptroller = IComptroller(_unitroller); // unitroller is a proxy for comptroller calls
    require(_unitroller != address(0), "Invalid comptroller address");
    ICompoundPriceOracle _oracle = IComptroller(_unitroller).oracle(); // pricefeed used by the comptroller
    require(address(_oracle) != address(0), "Failed to get price oracle");
    oracle = _oracle;
    weth = IERC20(wethAddress);
  }

  function isCeth(IcERC20 ctoken) internal view returns (bool) {
    return (keccak256(abi.encodePacked(ctoken.symbol())) ==
      keccak256(abi.encodePacked("cETH")));
  }

  //dealing with cEth special case
  function underlying(IcERC20 ctoken) internal view returns (IERC20) {
    require(ctoken.isCToken(), "Invalid ctoken address");
    if (isCeth(ctoken)) {
      // cETH has no underlying() function...
      return weth;
    } else {
      return IERC20(ctoken.underlying());
    }
  }

  function _approveLender(IcERC20 ctoken, uint amount) internal returns (bool) {
    IERC20 token = underlying(ctoken);
    return token.approve(address(ctoken), amount);
  }

  function _enterMarkets(address[] calldata ctokens) internal {
    uint[] memory results = comptroller.enterMarkets(ctokens);
    for (uint i = 0; i < ctokens.length; i++) {
      require(results[i] == 0, "Failed to enter market");
      IERC20 token = underlying(IcERC20(ctokens[i]));
      // adding ctoken.underlying --> ctoken mapping
      overlyings[token] = IcERC20(ctokens[i]);
    }
  }

  function _exitMarket(IcERC20 ctoken) internal {
    require(
      comptroller.exitMarket(address(ctoken)) == 0,
      "failed to exit marker"
    );
  }

  function _claimComp() internal {
    comptroller.claimComp(address(this));
  }

  function isPooled(IERC20 token) public view returns (bool) {
    IcERC20 ctoken = overlyings[token];
    return comptroller.checkMembership(address(this), ctoken);
  }

  /// @notice struct to circumvent stack too deep error in `maxGettableUnderlying` function
  struct Heap {
    uint ctokenBalance;
    uint cDecimals;
    uint decimals;
    uint exchangeRateMantissa;
    uint liquidity;
    uint collateralFactorMantissa;
    uint maxRedeemable;
    uint balanceOfUnderlying;
    uint priceMantissa;
    uint underlyingLiquidity;
    MathError mErr;
    uint errCode;
  }

  function heapError(Heap memory heap) private pure returns (bool) {
    return (heap.errCode != 0 || heap.mErr != MathError.NO_ERROR);
  }

  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)
  function maxGettableUnderlying(address _ctoken, address account)
    public
    view
    returns (uint, uint)
  {
    IcERC20 ctoken = IcERC20(_ctoken);
    Heap memory heap;
    // NB balance below is underestimated unless accrue interest was triggered earlier in the transaction
    (heap.errCode, heap.ctokenBalance, , heap.exchangeRateMantissa) = ctoken
      .getAccountSnapshot(address(this)); // underapprox
    heap.priceMantissa = oracle.getUnderlyingPrice(ctoken); //18 decimals

    // balanceOfUnderlying(A) : cA.balance * exchange_rate(cA,A)

    (heap.mErr, heap.balanceOfUnderlying) = mulScalarTruncate(
      Exp({mantissa: heap.exchangeRateMantissa}),
      heap.ctokenBalance // ctokens have 8 decimals precision
    );

    if (heapError(heap)) {
      return (0, 0);
    }

    // max amount of outbound_Tkn token than can be borrowed
    (
      heap.errCode,
      heap.liquidity, // is USD:18 decimals
      /*shortFall*/

    ) = comptroller.getAccountLiquidity(account); // underapprox

    // to get liquidity expressed in outbound_Tkn token instead of USD
    (heap.mErr, heap.underlyingLiquidity) = divScalarByExpTruncate(
      heap.liquidity,
      Exp({mantissa: heap.priceMantissa})
    );
    if (heapError(heap)) {
      return (0, 0);
    }
    (, heap.collateralFactorMantissa, ) = comptroller.markets(address(ctoken));

    // if collateral factor is 0 then any token can be redeemed from the pool w/o impacting borrow power
    // also true if market is not entered
    if (
      heap.collateralFactorMantissa == 0 ||
      !comptroller.checkMembership(account, ctoken)
    ) {
      return (heap.balanceOfUnderlying, heap.underlyingLiquidity);
    }

    // maxRedeem:[underlying] = liquidity:[USD / 18 decimals ] / (price(outbound_tkn):[USD.underlying^-1 / 18 decimals] * collateralFactor(outbound_tkn): [0-1] 18 decimals)
    (heap.mErr, heap.maxRedeemable) = divScalarByExpTruncate(
      heap.liquidity,
      mul_(
        Exp({mantissa: heap.collateralFactorMantissa}),
        Exp({mantissa: heap.priceMantissa})
      )
    );
    if (heapError(heap)) {
      return (0, 0);
    }
    heap.maxRedeemable = min(heap.maxRedeemable, heap.balanceOfUnderlying);
    // B|R = B - R*CF
    return (
      heap.maxRedeemable,
      sub_(
        heap.underlyingLiquidity, //borrow power
        mul_ScalarTruncate(
          Exp({mantissa: heap.collateralFactorMantissa}),
          heap.maxRedeemable
        )
      )
    );
  }

  function compoundRedeem(uint amountToRedeem, ML.SingleOrder calldata order)
    internal
    returns (uint)
  {
    IcERC20 outbound_cTkn = overlyings[IERC20(order.outbound_tkn)]; // this is 0x0 if outbound_tkn is not compound sourced.
    if (address(outbound_cTkn) == address(0)) {
      return amountToRedeem;
    }
    uint errorCode = outbound_cTkn.redeemUnderlying(amountToRedeem); // accrues interests
    if (errorCode == 0) {
      //compound redeem was a success
      // if ETH was redeemed, one needs to convert them into wETH
      if (isCeth(outbound_cTkn)) {
        weth.deposit{value: amountToRedeem}();
      }
      return 0;
    } else {
      //compound redeem failed
      emit ErrorOnRedeem(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        amountToRedeem,
        errorCode
      );
      return amountToRedeem;
    }
  }

  function _mint(uint amount, IcERC20 ctoken) internal returns (uint errCode) {
    if (isCeth(ctoken)) {
      // turning `amount` of wETH into ETH
      try weth.withdraw(amount) {
        // minting amount of ETH into cETH
        ctoken.mint{value: amount}();
      } catch {
        if (amount == weth.balanceOf(address(this))) {}
        require(false);
      }
    } else {
      // Approve transfer on the ERC20 contract (not needed if cERC20 is already approved for `this`)
      // IERC20(ctoken.underlying()).approve(ctoken, amount);
      errCode = ctoken.mint(amount); // accrues interest
    }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  function compoundMint(uint amount, ML.SingleOrder calldata order)
    internal
    returns (uint missing)
  {
    IcERC20 ctoken = overlyings[IERC20(order.inbound_tkn)];
    uint errCode = _mint(amount, ctoken);
    // Mint ctokens
    if (errCode != 0) {
      emit ErrorOnMint(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        amount,
        errCode
      );
      missing = amount;
    }
  }
}
