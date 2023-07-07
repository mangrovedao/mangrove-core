// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

// Avoid name shadowing
import "../MiscToString.sol";


  import {OfferPacked, OfferUnpacked} from "mgv_src/preprocessed/MgvOffer.post.sol";
  function toString(OfferPacked __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(OfferUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Offer{","prev: ", vm.toString(__unpacked.prev), ", ", "next: ", vm.toString(__unpacked.next), ", ", "tick: ", toString(__unpacked.tick), ", ", "gives: ", vm.toString(__unpacked.gives),"}");
  }

  import {OfferDetailPacked, OfferDetailUnpacked} from "mgv_src/preprocessed/MgvOfferDetail.post.sol";
  function toString(OfferDetailPacked __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(OfferDetailUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("OfferDetail{","maker: ", vm.toString(__unpacked.maker), ", ", "gasreq: ", vm.toString(__unpacked.gasreq), ", ", "offer_gasbase: ", vm.toString(__unpacked.offer_gasbase), ", ", "gasprice: ", vm.toString(__unpacked.gasprice),"}");
  }

  import {GlobalPacked, GlobalUnpacked} from "mgv_src/preprocessed/MgvGlobal.post.sol";
  function toString(GlobalPacked __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(GlobalUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Global{","monitor: ", vm.toString(__unpacked.monitor), ", ", "useOracle: ", vm.toString(__unpacked.useOracle), ", ", "notify: ", vm.toString(__unpacked.notify), ", ", "gasprice: ", vm.toString(__unpacked.gasprice), ", ", "gasmax: ", vm.toString(__unpacked.gasmax), ", ", "dead: ", vm.toString(__unpacked.dead),"}");
  }

  import {LocalPacked, LocalUnpacked} from "mgv_src/preprocessed/MgvLocal.post.sol";
  function toString(LocalPacked __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(LocalUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Local{","active: ", vm.toString(__unpacked.active), ", ", "fee: ", vm.toString(__unpacked.fee), ", ", "density: ", toString(__unpacked.density), ", ", "tick: ", toString(__unpacked.tick), ", ", "level0: ", toString(__unpacked.level0), ", ", "level2: ", toString(__unpacked.level2), ", ", "offer_gasbase: ", vm.toString(__unpacked.offer_gasbase), ", ", "lock: ", vm.toString(__unpacked.lock), ", ", "best: ", vm.toString(__unpacked.best), ", ", "last: ", vm.toString(__unpacked.last),"}");
  }