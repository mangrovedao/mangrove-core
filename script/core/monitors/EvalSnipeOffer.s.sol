// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2, toFixed, console2 as console} from "@mgv/lib/Test2.sol";
import {VolumeData, IMangrove} from "@mgv/src/periphery/MgvReader.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import "@mgv/src/core/MgvLib.sol";

/**
 * Script simulates a series of cleans on the offer at coordinate (TKN_OUT, TKN_IN, OFFER_ID)
 */
/**
 * It will try various quantities starting with taker gives 0 and outputs success or failure
 */

contract EvalCleanOffer is Test2, Deployer {
  receive() external payable {}

  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      olKey: OLKey(envAddressOrName("TKN_OUT"), envAddressOrName("TKN_IN"), vm.envUint("TICK_SPACING")),
      offerId: vm.envUint("OFFER_ID")
    });
  }

  struct Heap {
    Offer offer;
    OfferDetail details;
    MgvLib.CleanTarget[] target;
    uint takerWants;
  }

  function innerRun(IMangrove mgv, OLKey memory olKey, uint offerId) public {
    IERC20 inbTkn = IERC20(olKey.inbound_tkn);
    Heap memory heap;
    heap.offer = mgv.offers(olKey, offerId);
    heap.details = mgv.offerDetails(olKey, offerId);

    deal(address(inbTkn), address(this), heap.offer.wants());
    inbTkn.approve(address(mgv), heap.offer.wants());

    for (uint i = 0; i < 11; i++) {
      uint s = vm.snapshot();
      if (i == 0) {
        heap.takerWants = 0;
      } else {
        heap.takerWants = heap.offer.gives() / i;
      }
      heap.target = wrap_dynamic(MgvLib.CleanTarget(offerId, heap.offer.tick(), heap.details.gasreq(), heap.takerWants));
      _gas();
      string memory fill_str = i == 0 ? "0" : string.concat(vm.toString(11 - i), "/10");
      (uint successes, uint bounty) = mgv.cleanByImpersonation(olKey, heap.target, address(this));
      uint g = gas_(true);
      if (successes == 0) {
        console.log("\u274c %s fill (%s %s)", fill_str, toFixed(heap.takerWants, inbTkn.decimals()), inbTkn.symbol());
        console.log("Clean gas cost: %d, bounty: %s native tokens", g, toFixed(bounty, 18));
      } else {
        console.log("\u2705 %s fill", fill_str);
      }
      require(vm.revertTo(s), "revert to snapshot failed");
    }
  }
}
