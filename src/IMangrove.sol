// SPDX-License-Identifier: Unlicense
// This file was manually adapted from a file generated by abi-to-sol. It must
// be kept up-to-date with the actual Mangrove interface. Fully automatic
// generation is not yet possible due to user-generated types in the external
// interface lost in the abi generation.

pragma solidity >=0.7.0 <0.9.0;

pragma experimental ABIEncoderV2;

import {MgvLib, MgvStructs, IMaker, OLKey} from "./MgvLib.sol";
import "./MgvLib.sol" as MgvLibWrapper;

interface IMangrove {
  event Approval(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed tickScale,
    address owner,
    address spender,
    uint value
  );
  event Credit(address indexed maker, uint amount);
  event Debit(address indexed maker, uint amount);
  event Kill();
  event NewMgv();
  event OfferFail(bytes32 indexed olKeyHash, uint id, address taker, uint takerWants, uint takerGives, bytes32 mgvData);
  event OfferRetract(bytes32 indexed olKeyHash, uint id, bool deprovision);
  event OfferSuccess(bytes32 indexed olKeyHash, uint id, address taker, uint takerWants, uint takerGives);
  event OfferWrite(
    bytes32 indexed olKeyHash, address maker, int logPrice, uint gives, uint gasprice, uint gasreq, uint id
  );
  event OrderComplete(
    bytes32 indexed olKeyHash, address taker, uint takerGot, uint takerGave, uint penalty, uint feePaid
  );
  event OrderStart();
  event PosthookFail(bytes32 indexed olKeyHash, uint offerId, bytes32 posthookData);
  event SetActive(bytes32 indexed olKeyHash, bool value);
  event SetDensityFixed(bytes32 indexed olKeyHash, uint value);
  event SetFee(bytes32 indexed olKeyHash, uint value);
  event SetGasbase(bytes32 indexed olKeyHash, uint offer_gasbase);
  event SetGasmax(uint value);
  event SetGasprice(uint value);
  event SetGovernance(address value);
  event SetMonitor(address value);
  event SetNotify(bool value);
  event SetUseOracle(bool value);

  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function PERMIT_TYPEHASH() external view returns (bytes32);

  function withdrawERC20(address tokenAddress, uint value) external;
  function activate(OLKey memory olKey, uint fee, uint density, uint offer_gasbase) external;

  function allowances(address, address, address, address) external view returns (uint);

  function approve(address outbound_tkn, address inbound_tkn, address spender, uint value) external returns (bool);

  function balanceOf(address) external view returns (uint);

  function best(OLKey memory olKey) external view returns (uint);

  function config(OLKey memory olKey) external view returns (MgvStructs.GlobalPacked, MgvStructs.LocalPacked);

  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory global, MgvStructs.LocalUnpacked memory local);

  function deactivate(OLKey memory olKey) external;

  function flashloan(MgvLib.SingleOrder memory sor, address taker) external returns (uint gasused, bytes32 makerData);

  function fund(address maker) external payable;

  function fund() external payable;

  function governance() external view returns (address);

  function isLive(MgvStructs.OfferPacked offer) external pure returns (bool);

  function kill() external;

  function locked(OLKey memory olKey) external view returns (bool);

  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint fee);

  function marketOrderByPrice(OLKey memory olKey, uint maxPrice, uint fillVolume, bool fillWants)
    external
    returns (uint, uint, uint, uint);

  function marketOrderByLogPrice(OLKey memory olKey, int maxPrice_e18, uint fillVolume, bool fillWants)
    external
    returns (uint, uint, uint, uint);

  function marketOrderForByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function marketOrderForByPrice(OLKey memory olKey, uint maxPrice_e18, uint fillVolume, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function marketOrderForByLogPrice(OLKey memory olKey, int logPrice, uint fillVolume, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint);

  function newOfferByLogPrice(OLKey memory olKey, int logPrice, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint);

  function nonces(address) external view returns (uint);

  function offerDetails(OLKey memory olKey, uint) external view returns (MgvStructs.OfferDetailPacked);

  function offerInfo(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail);

  function offers(OLKey memory olKey, uint) external view returns (MgvStructs.OfferPacked);

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
}
