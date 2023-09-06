// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, IMgvMonitor, MgvStructs, IERC20, Leaf, Field, Density, DensityLib, OLKey} from "./MgvLib.sol";
import "mgv_src/MgvCommon.sol";

// Contains view functions, to reduce Mangrove contract size
contract MgvView is MgvCommon {
  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offerLists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey)
    public
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local)
  {
    unchecked {
      (_global, _local,) = _config(olKey);
      unlockedMarketOnly(_local);
    }
  }

  /* Reading the global configuration. In addition, a parameter (`gasprice`) may be read from the oracle. */
  function configGlobal() public view returns (MgvStructs.GlobalPacked _global) {
    unchecked {
      (_global,,) = _config(OLKey(address(0), address(0), 0));
    }
  }

  function balanceOf(address maker) external view returns (uint balance) {
    balance = _balanceOf[maker];
  }

  function leafs(OLKey memory olKey, int index) external view returns (Leaf) {
    OfferList storage offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(offerList.local);
    return offerList.leafs[index];
  }

  function level0(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;
    unlockedMarketOnly(local);

    if (local.bestTick().level0Index() == index) {
      return local.level0();
    } else {
      return offerList.level0[index];
    }
  }

  function level1(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;
    unlockedMarketOnly(local);

    if (local.bestTick().level1Index() == index) {
      return local.level1();
    } else {
      return offerList.level1[index];
    }
  }

  function level2(OLKey memory olKey) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;
    unlockedMarketOnly(local);
    return offerLists[olKey.hash()].level2;
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory _global, MgvStructs.LocalUnpacked memory _local)
  {
    unchecked {
      (MgvStructs.GlobalPacked __global, MgvStructs.LocalPacked __local) = config(olKey);
      unlockedMarketOnly(__local);
      _global = __global.to_struct();
      _local = __local.to_struct();
    }
  }

  /* Returns the global configuration in an ABI-compatible struct. Should not be called internally. */
  function configGlobalInfo() external view returns (MgvStructs.GlobalUnpacked memory _global) {
    unchecked {
      MgvStructs.GlobalPacked __global = configGlobal();
      _global = __global.to_struct();
    }
  }

  /* Convenience function to check whether given an offer list is locked */
  function locked(OLKey memory olKey) external view returns (bool) {
    return offerLists[olKey.hash()].local.lock();
  }

  /* # Read functions */
  /* Convenience function to get best offer of the given offerList */
  function best(OLKey memory olKey) external view returns (uint offerId) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked local = offerList.local;
      unlockedMarketOnly(local);
      return offerList.leafs[local.bestTick().leafIndex()].getNextOfferId();
    }
  }

  /* Convenience function to get an offer in packed format */
  function offers(OLKey memory olKey, uint offerId) external view returns (MgvStructs.OfferPacked offer) {
    OfferList storage offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(offerList.local);
    return offerList.offerData[offerId].offer;
  }

  /* Convenience function to get an offer detail in packed format */
  function offerDetails(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked offerDetail)
  {
    OfferList storage offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(offerList.local);
    return offerList.offerData[offerId].detail;
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offerLists[outbound_tkn][inbound_tkn].offers` and `offerLists[outbound_tkn][inbound_tkn].offerDetails` instead. */
  function offerInfo(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail)
  {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(offerList.local);
      OfferData storage offerData = offerList.offerData[offerId];
      offer = offerData.offer.to_struct();
      offerDetail = offerData.detail.to_struct();
    }
  }

  /* Permit-related view functions */

  function allowances(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint allowance)
  {
    allowance = _allowances[outbound_tkn][inbound_tkn][owner][spender];
  }

  function nonces(address owner) external view returns (uint nonce) {
    nonce = _nonces[owner];
  }

  // Note: the accessor for DOMAIN_SEPARATOR is defined in MgvStorage
  function PERMIT_TYPEHASH() external pure returns (bytes32) {
    return _PERMIT_TYPEHASH;
  }
}
