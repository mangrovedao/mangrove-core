// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, IMgvMonitor, MgvStructs, IERC20, Leaf, Field, Density, DensityLib, OLKey} from "./MgvLib.sol";
import "mgv_src/MgvCommon.sol";

// Contains view and gov functions, to reduce Mangrove contract size
contract MgvAppendix is MgvCommon {
  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offerLists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey)
    public
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local)
  {
    unchecked {
      (_global, _local,) = _config(olKey);
    }
  }

  function balanceOf(address maker) external view returns (uint balance) {
    balance = _balanceOf[maker];
  }

  function leafs(OLKey memory olKey, int index) external view returns (Leaf) {
    return offerLists[olKey.hash()].leafs[index];
  }

  function level0(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;

    if (local.bestTick().level0Index() == index) {
      return local.level0();
    } else {
      return offerList.level0[index];
    }
  }

  function level1(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;

    if (local.bestTick().level1Index() == index) {
      return local.level1();
    } else {
      return offerList.level1[index];
    }
  }

  function level2(OLKey memory olKey) external view returns (Field) {
    return offerLists[olKey.hash()].local.level2();
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory _global, MgvStructs.LocalUnpacked memory _local)
  {
    unchecked {
      (MgvStructs.GlobalPacked __global, MgvStructs.LocalPacked __local) = config(olKey);
      _global = __global.to_struct();
      _local = __local.to_struct();
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
      return offerList.leafs[offerList.local.bestTick().leafIndex()].getNextOfferId();
    }
  }

  /* Convenience function to get an offer in packed format */
  function offers(OLKey memory olKey, uint offerId) external view returns (MgvStructs.OfferPacked offer) {
    return offerLists[olKey.hash()].offerData[offerId].offer;
  }

  /* Convenience function to get an offer detail in packed format */
  function offerDetails(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked offerDetail)
  {
    return offerLists[olKey.hash()].offerData[offerId].detail;
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offerLists[outbound_tkn][inbound_tkn].offers` and `offerLists[outbound_tkn][inbound_tkn].offerDetails` instead. */
  function offerInfo(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail)
  {
    unchecked {
      OfferData storage offerData = offerLists[olKey.hash()].offerData[offerId];
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

  // Note: the accessor for DOMAIN_SEPARATOR is defined in MgvCommon
  function PERMIT_TYPEHASH() external pure returns (bytes32) {
    return _PERMIT_TYPEHASH;
  }

  /* Admin functions */
  /* ## `authOnly` check */

  function authOnly() internal view {
    unchecked {
      require(msg.sender == governance || msg.sender == address(this) || governance == address(0), "mgv/unauthorized");
    }
  }

  /* ## Transfer ERC20 tokens to governance.

    If this function is called while an order is executing, the reentrancy may prevent a party (taker in normal Mangrove, maker in inverted Mangrove) from receiving their tokens. This is fine as the order execution will then fail, and the tx will revert. So the most a malicious governance can do is render Mangrove unusable.
  */
  function withdrawERC20(address tokenAddress, uint value) external {
    authOnly();
    require(transferToken(tokenAddress, governance, value), "mgv/withdrawERC20Fail");
  }

  /* # Set configuration and Mangrove state */

  /* ## Locals */
  /* ### `active` */
  function activate(OLKey memory olKey, uint fee, uint densityFixed, uint offer_gasbase) public {
    unchecked {
      authOnly();
      OfferList storage offerList = offerLists[olKey.hash()];
      offerList.local = offerList.local.active(true);
      emit SetActive(olKey.hash(), true);
      setFee(olKey, fee);
      setDensityFixed(olKey, densityFixed);
      setGasbase(olKey, offer_gasbase);
    }
  }

  function deactivate(OLKey memory olKey) public {
    authOnly();
    OfferList storage offerList = offerLists[olKey.hash()];
    offerList.local = offerList.local.active(false);
    emit SetActive(olKey.hash(), false);
  }

  /* ### `fee` */
  function setFee(OLKey memory olKey, uint fee) public {
    unchecked {
      authOnly();
      /* `fee` is in basis points, i.e. in percents of a percent. */
      require(MgvStructs.Local.fee_check(fee), MgvStructs.Local.fee_size_error);
      OfferList storage offerList = offerLists[olKey.hash()];
      offerList.local = offerList.local.fee(fee);
      emit SetFee(olKey.hash(), fee);
    }
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` and oracle returns a valid density. */
  /* Density is given as a 96.32 fixed point number. It will be stored as a 9-bit float and be approximated towards 0. The maximum error is 20%. See `DensityLib` for more information. */
  function setDensityFixed(OLKey memory olKey, uint densityFixed) public {
    unchecked {
      authOnly();

      //+clear+
      OfferList storage offerList = offerLists[olKey.hash()];
      /* Checking the size of `density` is necessary to prevent overflow before storing density as a float. */
      require(DensityLib.checkFixedDensity(densityFixed), "mgv/config/density/128bits");

      offerList.local = offerList.local.densityFromFixed(densityFixed);
      emit SetDensityFixed(olKey.hash(), densityFixed);
    }
  }

  // FIXME Temporary, remove once all tooling has adapted to setDensityFixed
  function setDensity(OLKey memory olKey, uint density) external {
    setDensityFixed(olKey, density << DensityLib.FIXED_FRACTIONAL_BITS);
  }

  /* ### `gasbase` */
  function setGasbase(OLKey memory olKey, uint offer_gasbase) public {
    unchecked {
      authOnly();
      /* Checking the size of `offer_gasbase` is necessary to prevent a) data loss when copied to an `OfferDetail` struct, and b) overflow when used in calculations. */
      require(
        MgvStructs.Local.kilo_offer_gasbase_check(offer_gasbase / 1e3), MgvStructs.Local.kilo_offer_gasbase_size_error
      );
      // require(uint24(offer_gasbase) == offer_gasbase, "mgv/config/offer_gasbase/24bits");
      //+clear+
      OfferList storage offerList = offerLists[olKey.hash()];
      offerList.local = offerList.local.offer_gasbase(offer_gasbase);
      emit SetGasbase(olKey.hash(), offer_gasbase);
    }
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    unchecked {
      authOnly();
      internal_global = internal_global.dead(true);
      emit Kill();
    }
  }

  /* ### `gasprice` */
  /* Useless if `global.useOracle is != 0` */
  function setGasprice(uint gasprice) public {
    unchecked {
      authOnly();
      require(MgvStructs.Global.gasprice_check(gasprice), MgvStructs.Global.gasprice_size_error);

      //+clear+

      internal_global = internal_global.gasprice(gasprice);
      emit SetGasprice(gasprice);
    }
  }

  /* ### `gasmax` */
  function setGasmax(uint gasmax) public {
    unchecked {
      authOnly();
      /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
      require(MgvStructs.Global.gasmax_check(gasmax), MgvStructs.Global.gasmax_size_error);
      //+clear+
      internal_global = internal_global.gasmax(gasmax);
      emit SetGasmax(gasmax);
    }
  }

  /* ### `governance` */
  function setGovernance(address governanceAddress) public {
    unchecked {
      authOnly();
      require(governanceAddress != address(0), "mgv/config/gov/not0");
      governance = governanceAddress;
      emit SetGovernance(governanceAddress);
    }
  }

  /* ### `monitor` */
  function setMonitor(address monitor) public {
    unchecked {
      authOnly();
      internal_global = internal_global.monitor(monitor);
      emit SetMonitor(monitor);
    }
  }

  /* ### `useOracle` */
  function setUseOracle(bool useOracle) public {
    unchecked {
      authOnly();
      internal_global = internal_global.useOracle(useOracle);
      emit SetUseOracle(useOracle);
    }
  }

  /* ### `notify` */
  function setNotify(bool notify) public {
    unchecked {
      authOnly();
      internal_global = internal_global.notify(notify);
      emit SetNotify(notify);
    }
  }
}
