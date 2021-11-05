// SPDX-License-Identifier:	BSD-2-Clause

// SimpleOrale.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../interfaces/IOracle.sol";
import "./AccessControlled.sol";
import {IERC20} from "../../MgvLib.sol";

contract SimpleOracle is IOracle, AccessControlled {
  address reader; // if unset, anyone can read price
  IERC20 public immutable base_token;
  mapping(address => uint96) internal priceData;

  constructor(address _base) {
    try IERC20(_base).decimals() returns (uint8 d) {
      require(d != 0, "Invalid decimals number for Oracle base");
      base_token = IERC20(_base);
    } catch {
      revert("Invalid Oracle base address");
    }
  }

  function decimals() external view override returns (uint8) {
    return base_token.decimals();
  }

  function setReader(address _reader) external onlyAdmin {
    reader = _reader;
  }

  function setPrice(address token, uint price) external override onlyAdmin {
    require(uint96(price) == price, "price overflow");
    priceData[token] = uint96(price);
  }

  function getPrice(address token)
    external
    view
    override
    onlyCaller(reader)
    returns (uint96 price)
  {
    price = priceData[token];
    require(price != 0, "missing price data");
  }
}
