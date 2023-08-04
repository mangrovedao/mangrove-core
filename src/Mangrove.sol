// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs} from "./MgvLib.sol";

import {AbstractMangrove} from "./AbstractMangrove.sol";

/* <a id="Mangrove"></a> The `Mangrove` contract implements the "normal" version of Mangrove, where the taker flashloans the desired amount to each maker. Each time, makers are called after the loan. When the order is complete, each maker is called once again (with the orderbook unlocked). */
contract Mangrove is AbstractMangrove {
  constructor(address governance, uint gasprice, uint gasmax)
    AbstractMangrove(governance, gasprice, gasmax, "Mangrove")
  {}

  function executeEnd(MultiOrder memory mor, MgvLib.SingleOrder memory sor) internal override {}

  function beforePosthook(MgvLib.SingleOrder memory sor) internal override {}

  /* ## Flashloan */
  /*
     `flashloan` is for the 'normal' mode of operation. It:
     1. Flashloans `takerGives` `inbound_tkn` from the taker to the maker and returns false if the loan fails.
     2. Runs `offerDetail.maker`'s `execute` function.
     3. Returns the result of the operations, with optional makerData to help the maker debug.
   */
  function flashloan(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
    returns (uint gasused, bytes32 makerData)
  {
    unchecked {
      /* `flashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
      require(msg.sender == address(this), "mgv/flashloan/protected");
      /* The transfer taker -> maker is in 2 steps. First, taker->mgv. Then
       mgv->maker. With a direct taker->maker transfer, if one of taker/maker
       is blacklisted, we can't tell which one. We need to know which one:
       if we incorrectly blame the taker, a blacklisted maker can block a pair forever; if we incorrectly blame the maker, a blacklisted taker can unfairly make makers fail all the time. Of course we assume that Mangrove is not blacklisted. This 2-step transfer is incompatible with tokens that have transfer fees (more accurately, it uselessly incurs fees twice). */
      if (transferTokenFrom(sor.inbound_tkn, taker, address(this), sor.givesToThisOffer)) {
        if (transferToken(sor.inbound_tkn, sor.offerDetail.maker(), sor.givesToThisOffer)) {
          (gasused, makerData) = makerExecute(sor);
        } else {
          innerRevert([bytes32("mgv/makerReceiveFail"), bytes32(0), ""]);
        }
      } else {
        innerRevert([bytes32("mgv/takerTransferFail"), "", ""]);
      }
    }
  }
}
