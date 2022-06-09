// SPDX-License-Identifier:	BSD-2-Clause

// CompoundLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../../Modules/compound/CompoundModule.sol";
import "./SingleUser.sol";

abstract contract CompoundLender is SingleUser, CompoundModule {
  function approveLender(IcERC20 ctoken, uint amount) external onlyAdmin {
    require(_approveLender(ctoken, amount), "Lender/ApproveFail");
  }

  function enterMarkets(address[] calldata ctokens) external onlyAdmin {
    _enterMarkets(ctokens);
  }

  function exitMarket(IcERC20 ctoken) external onlyAdmin {
    _exitMarket(ctoken);
  }

  function claimComp() external onlyAdmin {
    _claimComp();
  }

  function mint(
    IcERC20 ctoken,
    uint amount,
    address
  ) external onlyAdmin {
    uint errCode = _mint(amount, ctoken);
    require(errCode == 0, "Lender/mintFailed");
  }

  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    if (!isPooled(IEIP20(order.outbound_tkn))) {
      // if flag says not to fetch liquidity on compound
      return amount;
    }
    // if outbound_tkn == weth, overlying will return cEth
    IcERC20 outbound_cTkn = overlyings[IEIP20(order.outbound_tkn)]; // this is 0x0 if outbound_tkn is not compound sourced.
    if (address(outbound_cTkn) == address(0)) {
      return amount;
    }
    (uint redeemable, ) = maxGettableUnderlying(
      address(outbound_cTkn),
      address(this)
    );
    if (redeemable < amount) {
      return amount; //give up if __get__ cannot withdraw enough
    }
    // else try redeem on compound
    if (compoundRedeem(amount, order) == 0) {
      // redeemAmount was transfered to `this`
      return 0;
    }
    return amount;
  }

  function __put__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    //optim
    if (!isPooled(IEIP20(order.inbound_tkn))) {
      return amount;
    }
    return compoundMint(amount, order);
  }
}
