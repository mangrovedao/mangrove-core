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
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function PERMIT_TYPEHASH() external pure returns (bytes32);

  function withdrawERC20(address tokenAddress, uint value) external;
  function activate(OLKey memory olKey, uint fee, uint densityFixed, uint offer_gasbase) external;

  function allowances(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint allowance);

  function approve(address outbound_tkn, address inbound_tkn, address spender, uint value) external returns (bool);

  function balanceOf(address maker) external view returns (uint balance);

  function best(OLKey memory olKey) external view returns (uint offerId);

  function config(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local);

  function configGlobal() external view returns (MgvStructs.GlobalPacked _global);

  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory _global, MgvStructs.LocalUnpacked memory _local);

  function configGlobalInfo() external view returns (MgvStructs.GlobalUnpacked memory _global);

  function deactivate(OLKey memory olKey) external;

  function flashloan(MgvLib.SingleOrder memory sor, address taker) external returns (uint gasused, bytes32 makerData);

  function internalCleanByImpersonation(
    OLKey memory olKey,
    uint offerId,
    int logPrice,
    uint gasreq,
    uint takerWants,
    address taker
  ) external returns (uint bounty);

  function fund(address maker) external payable;

  function fund() external payable;

  function governance() external view returns (address);

  function kill() external;

  function locked(OLKey memory olKey) external view returns (bool);

  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function marketOrderByLogPrice(OLKey memory olKey, int maxLogPrice, uint fillVolume, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function marketOrderForByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function marketOrderForByLogPrice(OLKey memory olKey, int logPrice, uint fillVolume, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function marketOrderByLogPrice(
    OLKey memory olKey,
    int maxLogPrice,
    uint fillVolume,
    bool fillWants,
    uint maxGasreqForFailingOffers
  ) external returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  function newOfferByLogPrice(OLKey memory olKey, int logPrice, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  function nonces(address owner) external view returns (uint nonce);

  function offerDetails(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked offerDetail);

  function offerInfo(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail);

  function offers(OLKey memory olKey, uint offerId) external view returns (MgvStructs.OfferPacked offer);

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

  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision) external returns (uint provision);

  function setDensityFixed(OLKey memory olKey, uint densityFixed) external;

  function setDensity(OLKey memory olKey, uint density) external;

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

  function cleanByImpersonation(OLKey memory olKey, MgvLib.CleanTarget[] calldata targets, address taker)
    external
    returns (uint successes, uint bounty);

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  function updateOfferByLogPrice(OLKey memory olKey, int logPrice, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  function withdraw(uint amount) external returns (bool noRevert);

  receive() external payable;

  function leafs(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Leaf);

  function level0(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Field);

  function level1(OLKey memory olKey, int index) external view returns (MgvLibWrapper.Field);

  function level2(OLKey memory olKey) external view returns (MgvLibWrapper.Field);

  fallback(bytes calldata callData) external returns (bytes memory);
}
