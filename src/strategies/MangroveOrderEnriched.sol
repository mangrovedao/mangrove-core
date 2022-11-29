// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOrderEnriched.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOrder} from "mgv_src/strategies/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

/**
 * @title This contract is a `MangroveOrder` enriched with the ability to retrieve all offers for each owner.
 */
contract MangroveOrderEnriched is MangroveOrder {
  /// @notice This maintains a mapping of owners to offers via linked offerIds.
  /// @dev `next[outbound_tkn][inbound_tkn][owner][id] = id'` with `next[outbound_tkn][inbound_tkn][owner][0]==0` iff owner has no offers on the semi book (out,in)
  mapping(IERC20 => mapping(IERC20 => mapping(address => mapping(uint => uint)))) next;

  /**
   * @notice `MangroveOrderEnriched`'s constructor
   * @param mgv The Mangrove deployment that is allowed to call `this` contract for trade execution and posthook and on which `this` contract will post offers.
   * @param deployer The address of the deployer will be set as admin for both this contract and the router, which are both `AccessControlled` contracts.
   */
  constructor(IMangrove mgv, address deployer) MangroveOrder(mgv, deployer, 30_000) {}

  /**
   * @notice Overridden to keep track of all offers for all owners.
   * @inheritdoc MangroveOrder
   */
  function __logOwnershipRelation__(address owner, IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    internal
    virtual
    override
  {
    // Push new offerId as the new head
    mapping(uint => uint) storage offers = next[outbound_tkn][inbound_tkn][owner];
    uint head = offers[0];
    offers[0] = offerId;
    if (head != 0) {
      offers[offerId] = head;
    }
  }

  /**
   * @notice Retrieves all offers for owner. We let this view function consume loads of gas units in exchange of a rather minimalistic state bookkeeping.
   * @param owner the owner to get all offers for
   * @param outbound_tkn the outbound token used to identify the order book
   * @param inbound_tkn the inbound token used to identify the order book
   * @return live ids of offers which are in the order book (see `Mangrove.isLive`)
   * @return dead ids of offers which are not in the order book
   */
  function offersOfOwner(address owner, IERC20 outbound_tkn, IERC20 inbound_tkn)
    external
    view
    returns (uint[] memory live, uint[] memory dead)
  {
    // Iterate all offers for owner twice since we cannot use array.push on memory arrays.
    // First to get number of live and dead to allocate arrays.
    mapping(uint => uint) storage offers = next[outbound_tkn][inbound_tkn][owner];
    uint head = offers[0];
    uint id = head;
    uint nLive = 0;
    uint nDead = 0;
    while (id != 0) {
      if (MGV.isLive(MGV.offers(address(outbound_tkn), address(inbound_tkn), id))) {
        nLive++;
      } else {
        nDead++;
      }
      id = offers[id];
    }
    // Repeat the loop with same logic, but now populate live and dead arrays.
    live = new uint[](nLive);
    dead = new uint[](nDead);
    id = head;
    nLive = 0;
    nDead = 0;
    while (id != 0) {
      if (MGV.isLive(MGV.offers(address(outbound_tkn), address(inbound_tkn), id))) {
        live[nLive++] = id;
      } else {
        dead[nDead++] = id;
      }
      id = offers[id];
    }
    return (live, dead);
  }
}
