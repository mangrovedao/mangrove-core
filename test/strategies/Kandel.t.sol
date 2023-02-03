// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {CoreKandelTest, CoreKandel, IMangrove, HasIndexedOffers} from "./CoreKandel.t.sol";
import {Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract KandelTest is CoreKandelTest {
  function test_dualWantsGivesOfOffer_max_bits_partial() public {
    // this verifies uint160(givesR) != givesR in dualWantsGivesOfOffer
    dualWantsGivesOfOffer_max_bits(true, 2);
  }

  function test_dualWantsGivesOfOffer_max_bits_full() public {
    // this verifies the edge cases:
    // uint160(givesR) != givesR
    // uint96(wants) != wants
    // uint96(gives) != gives
    // in dualWantsGivesOfOffer
    dualWantsGivesOfOffer_max_bits(false, 2);
  }

  // this makes share computation overflows in AaveKandel
  function dualWantsGivesOfOffer_max_bits(bool partialTake, uint numTakes) internal {
    uint8 spread = 8;
    uint8 pricePoints = 2 ** 8 - 1;

    uint96 base0 = 2 ** 96 - 1;
    uint96 quote0 = 2 ** 96 - 1;
    uint16 ratio = 2 ** 16 - 1;
    uint16 compoundRate = uint16(10 ** kdl.PRECISION());

    vm.prank(maker);
    kdl.retractOffers(0, 10);

    for (uint i = 0; i < numTakes; i++) {
      populateSingle({
        index: 0,
        base: base0,
        quote: quote0,
        pivotId: 0,
        lastBidIndex: 2,
        pricePoints: pricePoints,
        ratio: ratio,
        spread: spread,
        expectRevert: bytes("")
      });

      vm.prank(maker);
      kdl.setCompoundRates(compoundRate, compoundRate);
      // This only verifies KandelLib

      MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);

      deal($(quote), address(kdl), bid.gives());
      deal($(base), address(taker), bid.wants());

      uint amount = partialTake ? 1 ether : bid.wants();

      (uint successes,,,,) = sellToBestAs(taker, amount);
      assertEq(successes, 1, "offer should be sniped");
    }
    uint askOfferId = mgv.best($(base), $(quote));
    uint askIndex = kdl.indexOfOfferId(Ask, askOfferId);

    uint[] memory statuses = new uint[](askIndex+2);
    if (partialTake) {
      MgvStructs.OfferPacked ask = kdl.getOffer(Ask, askIndex);
      assertEq(1 ether * numTakes, ask.gives(), "ask should offer the provided 1 ether for each take");
      statuses[0] = uint(OfferStatus.Bid);
    }
    statuses[askIndex] = uint(OfferStatus.Ask);
    assertStatus(statuses, quote0, base0);
  }
}
