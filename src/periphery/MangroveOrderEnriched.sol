// SPDX-License-Identifier:	BSD-2-Clause

// Persistent.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "./MangroveOrder.sol";

contract MangroveOrderEnriched is MangroveOrder {
  // `next[out_tkn][in_tkn][owner][id] = id'` with `next[out_tkn][in_tkn][owner][0]==0` iff owner has now offers on the semi book (out,in)
  mapping(IERC20 => mapping(IERC20 => mapping(address => mapping(uint => uint)))) next;

  constructor(IMangrove _MGV, address deployer) MangroveOrder(_MGV, deployer) {}

  function __logOwnerShipRelation__(
    address owner,
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId
  ) internal virtual override {
    uint head = next[outbound_tkn][inbound_tkn][owner][0];
    next[outbound_tkn][inbound_tkn][owner][0] = offerId;
    if (head != 0) {
      next[outbound_tkn][inbound_tkn][owner][offerId] = head;
    }
  }

  // we let the following view function consume loads of gas units in exchange of a rather minimalistic state bookeeping
  function offersOfOwner(
    address owner,
    IERC20 outbound_tkn,
    IERC20 inbound_tkn
  ) external view returns (uint[] memory live, uint[] memory dead) {
    uint head = next[outbound_tkn][inbound_tkn][owner][0];
    uint id = head;
    uint n_live = 0;
    uint n_dead = 0;
    while (id != 0) {
      if (MGV.isLive(MGV.offers($(outbound_tkn), $(inbound_tkn), id))) {
        n_live++;
      } else {
        n_dead++;
      }
      id = next[outbound_tkn][inbound_tkn][owner][id];
    }
    live = new uint[](n_live);
    dead = new uint[](n_dead);
    id = head;
    n_live = 0;
    n_dead = 0;
    while (id != 0) {
      if (MGV.isLive(MGV.offers($(outbound_tkn), $(inbound_tkn), id))) {
        live[n_live++] = id;
      } else {
        dead[n_dead++] = id;
      }
      id = next[outbound_tkn][inbound_tkn][owner][id];
    }
    return (live, dead);
  }
}
