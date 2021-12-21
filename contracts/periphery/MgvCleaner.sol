// SPDX-License-Identifier:	AGPL-3.0

// MgvCleaner.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;
pragma abicoder v2;
import {MgvLib as ML, P} from "../MgvLib.sol";

interface MangroveLike {
  function snipesFor(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants,
    address taker
  )
    external
    returns (
      uint successes,
      uint takerGot,
      uint takerGave,
      uint bounty
    );

  function offerInfo(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId
  ) external view returns (P.OfferStruct memory, P.OfferStruct memory);
}

/* The purpose of the Cleaner contract is to execute failing offers and collect
 * their associated bounty. It takes an array of offers with same definition as
 * `Mangrove.snipes` and expects them all to fail or not execute. */

/* How to use:
   1) Ensure *your* address approved Mangrove for the token you will provide to the offer (`inbound_tkn`).
   2) Run `collect` on the offers that you detected were failing.

   You can adjust takerWants/takerGives and gasreq as needed.

   Note: in the current version you do not need to set MgvCleaner's allowance in Mangrove.
   TODO: add `collectWith` with an additional `taker` argument.
*/
contract MgvCleaner {
  MangroveLike immutable MGV;

  constructor(address _MGV) {
    MGV = MangroveLike(_MGV);
  }

  receive() external payable {}

  /* Returns the entire balance, not just the bounty collected */
  function collect(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants
  ) external returns (uint bal) { unchecked {
    (uint successes, , , ) = MGV.snipesFor(
      outbound_tkn,
      inbound_tkn,
      targets,
      fillWants,
      msg.sender
    );
    require(successes == 0, "mgvCleaner/anOfferDidNotFail");
    bal = address(this).balance;
    bool noRevert;
    (noRevert, ) = msg.sender.call{value: bal}("");
  }}
}
