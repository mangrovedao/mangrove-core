// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

/* The purpose of the Cleaner contract is to execute failing offers and collect
 * their associated bounty. It takes an array of offers and will attempt to clean them individually. */

/* How to use:
   1) Ensure *your* address approved Mangrove for the token you will provide to the offer (`inbound_tkn`).
   2) Run `collect` on the offers that you detected were failing.

   Instead of using your own address, you can use `collectByImpersonation` to impersonate another taker (`takerToImpersonate`) who has approved Mangrove for `inbound_tkn`. This allows borrowing that taker's `inbound_tkn` funds for cleaning instead of using `msg.sender`'s funds (who need not have any).

   Note: in the current version you do not need to set MgvCleaner's allowance in Mangrove. */
contract MgvCleaner {
  IMangrove immutable MGV;

  constructor(address mgv) {
    MGV = IMangrove(payable(mgv));
  }

  receive() external payable {}

  /* Returns the entire balance, not just the bounty collected */
  /* `cleans` multiple offers. It takes a `uint[4][]` as penultimate argument, with each array element of the form `[offerId,tick,fillVolume,offerGasreq]`. The return value is the bounty received by cleaning. 
  Note that we do not distinguish further between mismatched arguments/offer fields on the one hand, and an execution failure on the other. Still, a failed offer has to pay a penalty, and ultimately transaction logs explicitly mention execution failures (see `MgvLib.sol`). */
  function collect(address outbound_tkn, address inbound_tkn, uint[4][] calldata targets, bool fillWants)
    external
    returns (uint successes, uint bal)
  {
    unchecked {
      for (uint i = 0; i < targets.length; i++) {
        try MGV.clean(
          outbound_tkn,
          inbound_tkn,
          targets[i][0],
          int(targets[i][1]),
          targets[i][3],
          targets[i][2],
          fillWants,
          msg.sender
        ) {
          successes++;
        } catch {}
      }
      bal = address(this).balance;
      bool noRevert;
      (noRevert,) = msg.sender.call{value: bal}("");
    }
  }

  /* Collect bounties while impersonating another taker (`takerToImpersonate`) who has approved Mangrove for `inbound_tkn`. This allows borrowing that taker's `inbound_tkn` funds for cleaning instead of using `msg.sender`'s funds (who need not have any).
   * NB Returns the entire balance, not just the bounty collected
   */
  function collectByImpersonation(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants,
    address taker
  ) external returns (uint successes, uint bal) {
    unchecked {
      for (uint i = 0; i < targets.length; i++) {
        try MGV.clean(
          outbound_tkn, inbound_tkn, targets[i][0], int(targets[i][1]), targets[i][3], targets[i][2], fillWants, taker
        ) {
          successes++;
        } catch {}
      }
      bal = address(this).balance;
      bool noRevert;
      (noRevert,) = msg.sender.call{value: bal}("");
    }
  }
}
