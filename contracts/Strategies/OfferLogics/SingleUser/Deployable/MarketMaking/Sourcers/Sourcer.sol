// SPDX-License-Identifier:	BSD-2-Clause

//ITreasury.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "contracts/Strategies/interfaces/IEIP20.sol";
import "contracts/Strategies/utils/AccessControlled.sol";

abstract contract Sourcer is AccessControlled {
  mapping(address => bool) public makers;
  modifier onlyMakers() {
    require(makers[msg.sender], "Sourcer/unauthorized");
    _;
  }

  constructor(address deployer) AccessControlled(deployer) {}

  // gets `amount` of `token`s from liquidity source
  function pull(IEIP20 token, uint amount) external onlyMakers returns (uint) {
    return __pull__(token, amount);
  }

  function __pull__(IEIP20 token, uint amount) internal virtual returns (uint);

  // deposits `amount` of `token`s into liquidity source
  function flush(IEIP20[] calldata tokens) external onlyMakers {
    __flush__(tokens);
  }

  function __flush__(IEIP20[] calldata tokens) internal virtual;

  // checks amount of `token`s available in the liquidity source
  function balance(IEIP20 token) external view virtual returns (uint);

  // connect a maker contract to this sourcer
  function bind(address maker) external onlyAdmin {
    makers[maker] = true;
  }

  function unbind(address maker) external onlyAdmin {
    makers[maker] = false;
  }
}
