// SPDX-License-Identifier: Unlicense
// This file was manually adapted from a file generated by abi-to-sol. It must
// be kept up-to-date with the actual Mangrove interface. Fully automatic
// generation is not yet possible due to user-generated types in the external
// interface lost in the abi generation.

pragma solidity >=0.7.0 <0.9.0;

pragma experimental ABIEncoderV2;

import {MgvLib, MgvStructs, IMaker, OLKey, HasMgvEvents} from "./MgvLib.sol";
import "./MgvLib.sol" as MgvLibWrapper;

interface IMangrove is HasMgvEvents {
  // # Permit functions

  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function PERMIT_TYPEHASH() external pure returns (bytes32);

  function approve(address outbound_tkn, address inbound_tkn, address spender, uint value) external returns (bool);

  function allowances(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint allowance);

  function permit(
    address outbound_tkn,
    address inbound_tkn,
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function nonces(address owner) external view returns (uint nonce);

  // # Taker functions

  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function marketOrderByTick(OLKey memory olKey, int maxTick, uint fillVolume, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function marketOrderForByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function marketOrderForByTick(OLKey memory olKey, int tick, uint fillVolume, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  // # Cleaning functions

  function cleanByImpersonation(OLKey memory olKey, MgvLib.CleanTarget[] calldata targets, address taker)
    external
    returns (uint successes, uint bounty);

  // # Maker functions

  receive() external payable;

  function fund() external payable;

  function fund(address maker) external payable;

  function withdraw(uint amount) external returns (bool noRevert);

  function balanceOf(address maker) external view returns (uint balance);

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  function newOfferByTick(OLKey memory olKey, int tick, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  function updateOfferByTick(OLKey memory olKey, int tick, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  function marketOrderByTick(
    OLKey memory olKey,
    int maxTick,
    uint fillVolume,
    bool fillWants,
    uint maxGasreqForFailingOffers
  ) external returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision) external returns (uint provision);

  // # Global config view functions

  function global() external view returns (MgvStructs.GlobalPacked _global);

  // # Offer list view functions

  function local(OLKey memory olKey) external view returns (MgvStructs.LocalPacked _local);

  function config(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local);

  function locked(OLKey memory olKey) external view returns (bool);

  function best(OLKey memory olKey) external view returns (uint offerId);

  function olKeys(bytes32 olKeyHash) external view returns (OLKey memory olKey);

  // # Offer view functions

  function offers(OLKey memory olKey, uint offerId) external view returns (MgvStructs.OfferPacked offer);

  function offerDetails(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked offerDetail);

  function offerData(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferPacked offer, MgvStructs.OfferDetailPacked offerDetail);

  // # Governance functions

  function governance() external view returns (address);

  function activate(OLKey memory olKey, uint fee, uint density96X32, uint offer_gasbase) external;

  function deactivate(OLKey memory olKey) external;

  function kill() external;

  function setDensity96X32(OLKey memory olKey, uint density96X32) external;

  function setFee(OLKey memory olKey, uint fee) external;

  function setGasbase(OLKey memory olKey, uint offer_gasbase) external;

  function setGasmax(uint gasmax) external;

  function setMaxRecursionDepth(uint maxRecursionDepth) external;

  function setMaxGasreqForFailingOffers(uint maxGasreqForFailingOffers) external;

  function setGasprice(uint gasprice) external;

  function setGovernance(address governanceAddress) external;

  function setMonitor(address monitor) external;

  function setNotify(bool notify) external;

  function setUseOracle(bool useOracle) external;

  function withdrawERC20(address tokenAddress, uint value) external;

  // # Bin tree view functions

  function leafs(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Leaf);

  function level3(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Field);

  function level2(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Field);

  function level1(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Field);

  function root(OLKey memory olKey) external view returns (MgvLibWrapper.Field);

  // # Internal functions

  function flashloan(MgvLib.SingleOrder memory sor, address taker) external returns (uint gasused, bytes32 makerData);

  function internalCleanByImpersonation(
    OLKey memory olKey,
    uint offerId,
    int tick,
    uint gasreq,
    uint takerWants,
    address taker
  ) external returns (uint bounty);

  // Fall back function (forwards calls to `MgvAppendix`)
  fallback(bytes calldata callData) external returns (bytes memory);
}
