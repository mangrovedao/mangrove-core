// SPDX-License-Identifier:	BSD-2-Clause

//EOARouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "contracts/Strategies/utils/AccessControlled.sol";
import "contracts/Strategies/utils/TransferLib.sol";
import "./AbstractRouter.sol";

contract SimpleRouter is AbstractRouter(50_000) {
  // requires approval of `reserve`
  function __pull__(
    IEIP20 token,
    address reserve,
    address maker,
    uint amount,
    bool strict
  ) internal virtual override returns (uint pulled) {
    strict; // this pull strategy is only strict
    if (TransferLib.transferTokenFrom(token, reserve, maker, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  // requires approval of Maker
  function __push__(
    IEIP20 token,
    address reserve,
    address maker,
    uint amount
  ) internal virtual override {
    require(
      TransferLib.transferTokenFrom(token, maker, reserve, amount),
      "SimpleRouter/push/transferFail"
    );
  }

  /// this fonction is called immediately after a payable function has received funds
  /// NB this function should not be called when `reserve` is not tx.origin as this would give the possibility to an arbitrary
  /// contract to make the tx fail (in addition to potential reentrancy risks)
  function __push_native__(address reserve, uint amount)
    internal
    virtual
    override
    returns (bool success)
  {
    (success, ) = reserve.call{value: amount}("");
    require(success, "mgvOrder/mo/refundFail");
  }

  function reserveNativeBalance(address reserve)
    public
    view
    override
    returns (uint)
  {
    return reserve.balance;
  }

  function __withdrawToken__(
    IEIP20 token,
    address reserve,
    address to,
    uint amount
  ) internal virtual override returns (bool) {
    return TransferLib.transferTokenFrom(token, reserve, to, amount);
  }

  function reserveBalance(IEIP20 token, address reserve)
    external
    view
    override
    returns (uint)
  {
    return token.balanceOf(reserve);
  }
}
