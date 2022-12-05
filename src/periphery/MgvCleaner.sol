// SPDX-License-Identifier:	AGPL-3.0

// MgvCleaner.sol

// Copyright (C) 2021 ADDMA.
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

import {MgvLib, MgvStructs} from "../MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

/* The purpose of the Cleaner contract is to execute failing offers and collect
 * their associated bounty. It takes an array of offers with same definition as
 * `Mangrove.snipes` and expects them all to fail or not execute. */

/* How to use:
   1) Ensure *your* address approved Mangrove for the token you will provide to the offer (`inbound_tkn`).
   2) Run `collect` on the offers that you detected were failing.

   You can adjust takerWants/takerGives and gasreq as needed.

   Note: in the current version you do not need to set MgvCleaner's allowance in Mangrove. */
contract MgvCleaner {
  IMangrove immutable MGV;

  constructor(address mgv) {
    MGV = IMangrove(payable(mgv));
  }

  receive() external payable {}

  /* Returns the entire balance, not just the bounty collected */
  function collect(address outbound_tkn, address inbound_tkn, uint[4][] calldata targets, bool fillWants)
    external
    returns (uint bal)
  {
    unchecked {
      (uint successes,,,,) = MGV.snipesFor(outbound_tkn, inbound_tkn, targets, fillWants, msg.sender);
      require(successes == 0, "mgvCleaner/anOfferDidNotFail");
      bal = address(this).balance;
      bool noRevert;
      (noRevert,) = msg.sender.call{value: bal}("");
    }
  }

  /* Collect bounties while impersonating another taker (`takerToImpersonate`) who has approved Mangrove for `inbound_tkn`. This allows borrowing that taker's `inbound_tkn` funds for cleaning instead of using `msg.sender`'s funds (who need not have any).
   * NB This impersonation trick only works for sniping of failing offers. Mangrove checks whether `msg.sender` is approved to send orders/snipes for the impersonated taker and reverts if it isn't the case. That check just happens `after` the order has completed and if all taken offers failed, no actual `inbound_tkn` funds were used and the check succeeds, because `msg.sender` is approved for 0 `inbound_tkn`s.
   * NB Returns the entire balance, not just the bounty collected
   */
  function collectByImpersonation(address outbound_tkn, address inbound_tkn, uint[4][] calldata targets, bool fillWants, address takerToImpersonate)
    external
    returns (uint bal)
  {
    unchecked {
      (uint successes,,,,) = MGV.snipesFor(outbound_tkn, inbound_tkn, targets, fillWants, takerToImpersonate);
      require(successes == 0, "mgvCleaner/anOfferDidNotFail");
      bal = address(this).balance;
      bool noRevert;
      (noRevert,) = msg.sender.call{value: bal}("");
    }
  }
}
