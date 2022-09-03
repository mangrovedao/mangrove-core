// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/single_user/market_making/mango/Mango.sol";

/** @notice Initialize Mango offers on a given market */
/** Usage example: initialize MANGO_WETH_USDC */

// forge script --fork-url $MUMBAI_NODE_URL \
// --private-key $MUMBAI_TESTER_PRIVATE_KEY \
// --sig "run(address, uint, uint, uint, uint, uint)" \
// InitMango \
// 0x7D63939ce0Fa80cC69C129D337a978D0E1F354A1 \
// $(cast ff 18 0.25) \
// $(cast ff 6 1000) \
// 50 \
// 10 \
// 2

contract InitMango is Script {
  function run(
    address payable $mgo,
    uint default_base_amount, // for asks
    uint default_quote_amount, // for bids
    uint lastBidIndex,
    uint batch_size, // number of offers to be posted in the same tx
    uint cover_factor
  ) public {
    require(cover_factor * batch_size > 0, "invalid arguments");

    uint n = Mango($mgo).NSLOTS();
    {
      uint provAsk = Mango($mgo).getMissingProvision(
        Mango($mgo).BASE(), // outbound
        Mango($mgo).QUOTE(), // inbound
        type(uint).max, // to use offer gasreq
        0, // to use mangrove gasprice
        0 // not reposting an offer
      );
      uint provBid = Mango($mgo).getMissingProvision(
        Mango($mgo).QUOTE(), // outbound
        Mango($mgo).BASE(), // inbound
        type(uint).max, // to use offer gasreq
        0, // to use mangrove gasprice
        0 // not reposting an offer
      );

      // funding Mangrove
      IMangrove mgv = Mango($mgo).MGV();

      console.log(
        "Funding mangrove with",
        (provAsk + provBid) * n * cover_factor,
        "WEIs"
      );
      vm.broadcast();
      mgv.fund{value: (provAsk + provBid) * n * cover_factor}($mgo);
    }

    uint[] memory amounts = new uint[](n);
    uint[] memory pivotIds = new uint[](n);
    for (uint i = 0; i < amounts.length; i++) {
      if (i <= lastBidIndex) {
        amounts[i] = default_quote_amount;
      } else {
        amounts[i] = default_base_amount;
      }
    }
    uint remainder = n;
    for (uint i = 0; i < n / batch_size; i++) {
      vm.broadcast();
      Mango($mgo).initialize(
        true, // reset offers
        (n / 2) - 1, // last bid position
        batch_size * i, // from
        batch_size * (i + 1), // to
        [pivotIds, pivotIds],
        amounts
      );
      remainder -= batch_size;
    }
    if (remainder > 0) {
      vm.broadcast();
      Mango($mgo).initialize(
        true, // reset offers
        (n / 2) - 1, // last bid position
        n - remainder, // from
        n, // to
        [pivotIds, pivotIds],
        amounts
      );
    }
    // approving Mango to trade tester funds
    vm.startBroadcast();
    Mango($mgo).BASE().approve(address(Mango($mgo).router()), type(uint).max);
    Mango($mgo).QUOTE().approve(address(Mango($mgo).router()), type(uint).max);
    vm.stopBroadcast();
  }
}
