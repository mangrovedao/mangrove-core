// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import "mgv_src/strategies/routers/AbstractRouter.sol";

library MangoStorage {
  /**
   * Strat specific events
   */

  struct Layout {
    uint[] asks;
    uint[] bids;
    // amount of base (resp quote) tokens that failed to be published on the Market
    uint pending_base;
    uint pending_quote;
    // offerId -> index in ASKS/BIDS maps
    mapping(uint => uint) index_of_bid; // bidId -> index
    mapping(uint => uint) index_of_ask; // askId -> index
    // Price shift is in number of price increments (or decrements when shift < 0) since deployment of the strat.
    // e.g. for arithmetic progression, `shift = -3` indicates that Pmin is now (`QUOTE_0` - 3*`delta`)/`BASE_0`
    int shift;
    // parameter for price progression
    // NB for arithmetic progression, price(i+1) = price(i) + delta/`BASE_0`
    uint delta; // quote increment
    // triggers `__boundariesReached__` whenever amounts of bids/asks is below `min_buffer`
    uint min_buffer;
    // puts the strat into a (cancellable) state where it reneges on all incoming taker orders.
    // NB reneged offers are removed from Mangrove's OB
    bool paused;
    // Base and quote router contract
    AbstractRouter router;
  }

  function getStorage() internal pure returns (Layout storage st) {
    bytes32 storagePosition = keccak256("Mangrove.MangoStorage.Layout");
    assembly {
      st.slot := storagePosition
    }
  }

  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("MangoStorage/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }

  function quote_price_jumps(uint delta, uint position, uint quote_min) internal pure returns (uint) {
    return delta * position + quote_min;
  }
}
