// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Test2, console2 as console} from "mgv_lib/Test2.sol";
import {MgvReader, VolumeData, IMangrove} from "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

/**
 * Script simulates a series of snipes on the offer at coordinate (TKN_OUT, TKN_IN, OFFER_ID)
 */
/**
 * It will try various quantities starting with taker gives 0 and outputs success or failure
 */

contract EvalSnipeOffer is Test2, Deployer {
  receive() external payable {}

  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      inbTkn: IERC20(envAddressOrName("TKN_IN")),
      outTkn: IERC20(envAddressOrName("TKN_OUT")),
      offerId: vm.envUint("OFFER_ID")
    });
  }

  struct Heap {
    MgvStructs.OfferPacked offer;
    MgvStructs.OfferDetailPacked details;
    uint[4][] target;
    uint takerWants;
  }

  function innerRun(IMangrove mgv, IERC20 inbTkn, IERC20 outTkn, uint offerId) public {
    Heap memory heap;
    heap.offer = mgv.offers(address(outTkn), address(inbTkn), offerId);
    heap.details = mgv.offerDetails(address(outTkn), address(inbTkn), offerId);

    deal(address(inbTkn), address(this), heap.offer.wants());
    heap.target = new uint[4][](1);
    inbTkn.approve(address(mgv), heap.offer.wants());

    for (uint i = 0; i < 11; i++) {
      uint s = vm.snapshot();
      if (i == 0) {
        heap.takerWants = 0;
      } else {
        heap.takerWants = heap.offer.gives() / i;
      }
      heap.target[0] = [offerId, heap.takerWants, heap.offer.wants(), heap.details.gasreq()];
      _gas();
      string memory fill_str = i == 0 ? "0" : string.concat(vm.toString(11 - i), "/10");
      (uint successes,,, uint bounty,) = mgv.snipes(address(outTkn), address(inbTkn), heap.target, true);
      uint g = gas_(true);
      if (successes == 0) {
        console.log("\u274c %s fill (%s %s)", fill_str, toFixed(heap.takerWants, inbTkn.decimals()), inbTkn.symbol());
        console.log("Snipe gas cost: %d, bounty: %s native tokens", g, toFixed(bounty, 18));
      } else {
        console.log("\u2705 %s fill", fill_str);
      }
      require(vm.revertTo(s), "revert to snapshot failed");
    }
  }
}
