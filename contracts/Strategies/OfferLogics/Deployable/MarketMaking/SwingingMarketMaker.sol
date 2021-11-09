// SPDX-License-Identifier:	BSD-2-Clause

// SwingingMarketMaker.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../CompoundTrader.sol";

contract SwingingMarketMaker is CompoundTrader {
  event MissingPriceConverter(address token0, address token1);
  event NotEnoughProvision(uint amount);

  // price[B][A] : price of A in B = p(B|A) = volume of B obtained/volume of A given
  mapping(address => mapping(address => uint)) private price; // price[tk0][tk1] is in tk0 precision
  mapping(address => mapping(address => uint)) private offers;

  constructor(
    address _unitroller,
    address payable _MGV,
    address wethAddress
  ) CompoundLender(_unitroller, wethAddress) MangroveOffer(_MGV) {}

  // sets P(tk0|tk1)
  // one wants P(tk0|tk1).P(tk1|tk0) >= 1
  function setPrice(
    address tk0,
    address tk1,
    uint p
  ) external onlyAdmin {
    price[tk0][tk1] = p; // has tk0.decimals() decimals
  }

  function startStrat(
    address tk0,
    address tk1,
    uint gives // amount of tk0 (with tk0.decimals() decimals)
  ) external payable onlyAdmin {
    MGV.fund{value: msg.value}();
    require(repostOffer(tk0, tk1, gives), "Could not start strategy");
    IERC20(tk0).approve(address(MGV), uint(-1)); // approving MGV for tk0 transfer
    IERC20(tk1).approve(address(MGV), uint(-1)); // approving MGV for tk1 transfer
  }

  // at this stage contract has `received` amount in token0
  function repostOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint gives // in outbound_tkn
  ) internal returns (bool) {
    // computing how much inbound_tkn one should ask for `gives` amount of outbound tokens
    // NB p_10 has inbound_tkn.decimals() number of decimals
    uint p_10 = price[inbound_tkn][outbound_tkn];
    if (p_10 == 0) {
      // ! p_10 has the decimals of inbound_tkn
      emit MissingPriceConverter(inbound_tkn, outbound_tkn);
      return false;
    }
    uint wants = div_(
      mul_(p_10, gives), // p(base|quote).(gives:quote) : base
      10**(IERC20(outbound_tkn).decimals())
    ); // in base units
    uint offerId = offers[outbound_tkn][inbound_tkn];
    if (offerId == 0) {
      try
        this.newOffer(outbound_tkn, inbound_tkn, wants, gives, OFR_GASREQ, 0, 0)
      returns (uint id) {
        offers[outbound_tkn][inbound_tkn] = id;
        return true;
      } catch Error(string memory message) {
        emit PosthookFail(outbound_tkn, inbound_tkn, offerId, message);
        return false;
      }
    } else {
      try
        this.updateOffer(
          outbound_tkn,
          inbound_tkn,
          wants,
          gives,
          // offerId is already on the book so a good pivot
          OFR_GASREQ, // default value
          0, // default value
          offerId,
          offerId
        )
      {
        return true;
      } catch Error(string memory message) {
        emit PosthookFail(outbound_tkn, inbound_tkn, offerId, message);
        return false;
      }
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    override
  {
    address token0 = order.outbound_tkn;
    address token1 = order.inbound_tkn;
    uint offer_received = MP.offer_unpack_wants(order.offer); // amount with token1.decimals() decimals
    repostOffer({
      outbound_tkn: token1,
      inbound_tkn: token0,
      gives: offer_received
    });
  }

  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // checks whether `this` contract has enough `base` token
    uint missingGet = MangroveOffer.__get__(base, amount);
    // if not tries to fetch missing liquidity on compound using `CompoundTrader`'s strat
    return super.__get__(base, missingGet);
  }
}
