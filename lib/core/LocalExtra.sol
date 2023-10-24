// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {Bin,TickTreeLib,Field} from "@mgv/lib/core/TickTreeLib.sol";
import {Density, DensityLib} from "@mgv/lib/core/DensityLib.sol";
import {Local,LocalUnpacked,LocalLib} from "@mgv/src/preprocessed/Local.post.sol";



// cleanup-mask: 0s at location of fields to hide from maker, 1s elsewhere
uint constant HIDE_FIELDS_FROM_MAKER_MASK = ~(LocalLib.binPosInLeaf_mask_inv | LocalLib.level3_mask_inv | LocalLib.level2_mask_inv | LocalLib.level1_mask_inv | LocalLib.root_mask_inv | LocalLib.last_mask_inv);

/* Extra functions for local */
library LocalExtra {

  /* Sets the density in fixed-point 96X32 format (it is stored in floating-point, see `DensityLib` for more information). */
  function densityFrom96X32(Local local, uint density96X32) internal pure returns (Local) { unchecked {
    return local.density(DensityLib.from96X32(density96X32));
  }}

  /* Returns the gasbase in gas (it is stored in kilogas) */
  function offer_gasbase(Local local) internal pure returns (uint) { unchecked {
    return local.kilo_offer_gasbase() * 1e3;
  }}

  /* Sets the gasbase in gas (it is stored in kilogas) */
  function offer_gasbase(Local local,uint val) internal pure returns (Local) { unchecked {
    return local.kilo_offer_gasbase(val/1e3);
  }}

  /* Returns the bin that contains the best offer in \`local\`'s offer list */
  function bestBin(Local local) internal pure returns (Bin) { unchecked {
    return TickTreeLib.bestBinFromLocal(local);
  }}

  /* Erases field that give information about the current structure of the offer list. */
  function clearFieldsForMaker(Local local) internal pure returns (Local) { unchecked {
    return Local.wrap(
      Local.unwrap(local)
      & HIDE_FIELDS_FROM_MAKER_MASK);
  }}
}

/* Extra functions for the struct version of local */
library LocalUnpackedExtra {
  /* Sets the density in fixed-point 96X32 format (it is stored in floating-point, see `DensityLib` for more information). */
  function densityFrom96X32(LocalUnpacked memory local, uint density96X32) internal pure { unchecked {
    local.density = DensityLib.from96X32(density96X32);
  }}

  /* Returns the gasbase in gas (it is stored in kilogas) */
  function offer_gasbase(LocalUnpacked memory local) internal pure returns (uint) { unchecked {
    return local.kilo_offer_gasbase * 1e3;
  }}

  /* Sets the gasbase in gas (it is stored in kilogas) */
  function offer_gasbase(LocalUnpacked memory local,uint val) internal pure { unchecked {
    local.kilo_offer_gasbase = val/1e3;
  }}

  /* Returns the bin that contains the best offer in \`local\`'s offer list */
  function bestBin(LocalUnpacked memory local) internal pure returns (Bin) { unchecked {
    return TickTreeLib.bestBinFromBranch(local.binPosInLeaf,local.level3,local.level2,local.level1,local.root);
  }}
}