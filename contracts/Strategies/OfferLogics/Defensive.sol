// SPDX-License-Identifier:	BSD-2-Clause

// Defensive.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/IOracle.sol";

// import "hardhat/console.sol";

abstract contract Defensive is MangroveOffer {
  uint16 slippage_num;
  uint16 constant slippage_den = 10**4;
  IOracle public oracle;

  // emitted when no price data is available for given token
  event MissingPrice(address token);

  constructor(address _oracle) {
    require(!(_oracle == address(0)), "Invalid oracle address");
    oracle = IOracle(_oracle);
  }

  function setSlippage(uint _slippage) external onlyAdmin {
    require(uint16(_slippage) == _slippage, "Slippage overflow");
    require(uint16(_slippage) <= slippage_den, "Slippage should be <= 1");
    slippage_num = uint16(_slippage);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    uint offer_gives_REF = mul_(
      order.wants,
      oracle.getPrice(order.outbound_tkn) // returns price in oracle base units (i.e ETH or USD)
    );
    uint offer_wants_REF = mul_(
      order.gives,
      oracle.getPrice(order.inbound_tkn) // returns price is oracle base units (i.e ETH or USD)
    );
    // abort trade if price data is not available
    if (offer_gives_REF == 0) {
      emit MissingPrice(order.outbound_tkn);
      return false;
    }
    if (offer_wants_REF == 0) {
      emit MissingPrice(order.inbound_tkn);
      return false;
    }
    // if offer_gives_REF * (1-slippage) > offer_wants_REF one is getting arb'ed
    // i.e slippage_den * OGR - slippage_num * OGR > OWR * slippage_den
    return (sub_(
      mul_(offer_gives_REF, slippage_den),
      mul_(offer_gives_REF, slippage_num)
    ) <= mul_(offer_wants_REF, slippage_den));
  }
}
