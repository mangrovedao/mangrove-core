// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

// Avoid name shadowing
import "../MiscToString.sol";


  import {Offer, OfferUnpacked} from "mgv_src/preprocessed/Offer.post.sol";
  function toString(Offer __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(OfferUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Offer{","prev: ", vm.toString(__unpacked.prev), ", ", "next: ", vm.toString(__unpacked.next), ", ", "bin: ", toString(__unpacked.bin), ", ", "gives: ", vm.toString(__unpacked.gives),"}");
  }

  import {OfferDetail, OfferDetailUnpacked} from "mgv_src/preprocessed/MgvOfferDetail.post.sol";
  function toString(OfferDetail __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(OfferDetailUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("OfferDetail{","maker: ", vm.toString(__unpacked.maker), ", ", "gasreq: ", vm.toString(__unpacked.gasreq), ", ", "offer_gasbase: ", vm.toString(__unpacked.offer_gasbase), ", ", "gasprice: ", vm.toString(__unpacked.gasprice),"}");
  }

  import {Global, GlobalUnpacked} from "mgv_src/preprocessed/MgvGlobal.post.sol";
  function toString(Global __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(GlobalUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Global{","monitor: ", vm.toString(__unpacked.monitor), ", ", "useOracle: ", vm.toString(__unpacked.useOracle), ", ", "notify: ", vm.toString(__unpacked.notify), ", ", "gasprice: ", vm.toString(__unpacked.gasprice), ", ", "gasmax: ", vm.toString(__unpacked.gasmax), ", ", "dead: ", vm.toString(__unpacked.dead),"}");
  }

  import {Local, LocalUnpacked} from "mgv_src/preprocessed/MgvLocal.post.sol";
  function toString(Local __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(LocalUnpacked memory __unpacked) pure returns (string memory) {
    return string.concat("Local{","active: ", vm.toString(__unpacked.active), ", ", "fee: ", vm.toString(__unpacked.fee), ", ", "density: ", toString(__unpacked.density), ", ", "bin: ", toString(__unpacked.bin), ", ", "level3: ", toString(__unpacked.level3), ", ", "level1: ", toString(__unpacked.level1), ", ", "offer_gasbase: ", vm.toString(__unpacked.offer_gasbase), ", ", "lock: ", vm.toString(__unpacked.lock), ", ", "best: ", vm.toString(__unpacked.best), ", ", "last: ", vm.toString(__unpacked.last),"}");
  }