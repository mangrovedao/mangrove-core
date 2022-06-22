// SPDX-License-Identifier:	BSD-2-Clause

//EOARouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "contracts/strategies/utils/AccessControlled.sol";
import "contracts/strategies/utils/TransferLib.sol";
import "../AbstractRouter.sol";

contract EOARouter is AbstractRouter {
  address public immutable SOURCE;

  constructor(address deployer) AbstractRouter(deployer) {
    SOURCE = deployer;
  }

  // requires approval of SOURCE deployer
  function __pull__(IEIP20 token, uint amount)
    internal
    virtual
    override
    returns (uint missing)
  {
    if (TransferLib.transferTokenFrom(token, SOURCE, msg.sender, amount)) {
      return 0;
    } else {
      return amount;
    }
  }

  // requires approval of Maker
  function __flush__(IEIP20[] calldata tokens) internal virtual override {
    for (uint i = 0; i < tokens.length; i++) {
      uint amount = tokens[i].balanceOf(msg.sender);
      require(
        TransferLib.transferTokenFrom(tokens[i], msg.sender, SOURCE, amount),
        "EOARouter/flush/transferFail"
      );
    }
  }

  function balance(IEIP20 token) external view override returns (uint) {
    return token.balanceOf(SOURCE);
  }
}
