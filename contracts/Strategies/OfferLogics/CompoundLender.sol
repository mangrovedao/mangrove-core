// SPDX-License-Identifier:	BSD-2-Clause

// CompoundLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/compound/ICompound.sol";

import "hardhat/console.sol";

abstract contract CompoundLender is MangroveOffer {
  event ErrorOnRedeem(address ctoken, uint amount, uint errorCode);
  event ErrorOnMint(address ctoken, uint amount, uint errorCode);
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

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with compound
  /**************************************************************************/

  ///@notice approval of ctoken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function approveLender(address ctoken, uint amount) external onlyAdmin {
    IERC20 token = underlying(IcERC20(ctoken));
    token.approve(ctoken, amount);
  }

  function mint(address ctoken, uint amount) external onlyAdmin {
    compoundMint(IcERC20(ctoken), amount);
  }

  function redeem(address ctoken, uint amount) external onlyAdmin {
    require(compoundRedeem(IcERC20(ctoken), amount) == 0);
  }

  function isCeth(IcERC20 ctoken) internal view returns (bool) {
    return (keccak256(abi.encodePacked(ctoken.symbol())) ==
      keccak256(abi.encodePacked("cETH")));
  }

  //dealing with cEth special case
  function underlying(IcERC20 ctoken) internal returns (IERC20) {
    require(ctoken.isCToken(), "Invalid ctoken address");
    if (isCeth(ctoken)) {
      // cETH has no underlying() function...
      return weth;
    } else {
      return IERC20(ctoken.underlying());
    }
  }

  ///@notice enters markets in order to be able to use assets as collateral
  function enterMarkets(address[] calldata ctokens) external onlyAdmin {
    uint[] memory results = comptroller.enterMarkets(ctokens);
    for (uint i = 0; i < ctokens.length; i++) {
      require(results[i] == 0, "Failed to enter market");
      IcERC20 ctoken = IcERC20(ctokens[i]);
      IERC20 token = underlying(ctoken);
      // adding ctoken.underlying --> ctoken mapping
      overlyings[token] = ctoken;
    }
  }

  function isPooled(address token) public view returns (bool) {
    IcERC20 ctoken = overlyings[IERC20(token)];
    return comptroller.checkMembership(address(this), ctoken);
  }

  ///@notice exits markets
  function exitMarket(address ctoken) external onlyAdmin {
    require(comptroller.exitMarket(ctoken) == 0, "failed to exit marker");
  }

  ///@notice claims COMP token for `this` contract. One may afterward transfer them using `MangroveOffer.transferToken`
  function claimComp() external onlyAdmin {
    comptroller.claimComp(address(this));
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
  function maxGettableUnderlying(address _ctoken)
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

    ) = comptroller.getAccountLiquidity(address(this)); // underapprox

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
      !comptroller.checkMembership(address(this), ctoken)
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

  ///@notice method to get `outbound_tkn` during makerExecute
  ///@param outbound_tkn address of the ERC20 managing `outbound_tkn` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    if (!isPooled(address(outbound_tkn))) {
      // if flag says not to fetch liquidity on compound
      return amount;
    }
    // if outbound_tkn == weth, overlying will return cEth
    IcERC20 outbound_cTkn = IcERC20(overlyings[outbound_tkn]); // this is 0x0 if outbound_tkn is not compound sourced.
    if (address(outbound_cTkn) == address(0)) {
      return amount;
    }
    outbound_cTkn.accrueInterest();
    (uint redeemable, ) = maxGettableUnderlying(address(outbound_cTkn));

    uint redeemAmount = min(redeemable, amount);

    if (compoundRedeem(outbound_cTkn, redeemAmount) == 0) {
      // redeemAmount was transfered to `this`
      return (amount - redeemAmount);
    }
    return amount;
  }

  function compoundRedeem(IcERC20 coutbound_tkn, uint amountToRedeem)
    internal
    returns (uint)
  {
    uint errorCode = coutbound_tkn.redeemUnderlying(amountToRedeem); // accrues interests
    if (errorCode == 0) {
      //compound redeem was a success
      // if ETH was redeemed, one needs to convert them into wETH
      if (isCeth(coutbound_tkn)) {
        weth.deposit{value: amountToRedeem}();
      }
      return 0;
    } else {
      //compound redeem failed
      emit ErrorOnRedeem(address(coutbound_tkn), amountToRedeem, errorCode);
      return amountToRedeem;
    }
  }

  function __put__(IERC20 inbound_tkn, uint amount) internal virtual override {
    //optim
    if (amount == 0 || !isPooled(address(inbound_tkn))) {
      return;
    }
    IcERC20 ctoken = IcERC20(overlyings[inbound_tkn]);
    if (address(ctoken) != address(0)) {
      compoundMint(ctoken, amount);
    }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `ctoken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve ctoken in order to mint
  function compoundMint(IcERC20 ctoken, uint amount) internal {
    if (isCeth(ctoken)) {
      // turning `amount` of wETH into ETH
      weth.withdraw(amount);
      // minting amount of ETH into cETH
      ctoken.mint{value: amount}();
    } else {
      // Approve transfer on the ERC20 contract (not needed if cERC20 is already approved for `this`)
      // IERC20(ctoken.underlying()).approve(ctoken, amount);
      uint errCode = ctoken.mint(amount); // accrues interest
      // Mint ctokens
      if (errCode != 0) {
        emit ErrorOnMint(address(ctoken), amount, errCode);
      }
    }
  }
}
