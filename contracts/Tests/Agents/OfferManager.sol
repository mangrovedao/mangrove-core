// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../AbstractMangrove.sol";
//import "../../MgvLib.sol";
import {IERC20, IMaker, ITaker, MgvLib as ML, HasMgvEvents, IMgvMonitor} from "../../MgvLib.sol";
import {MgvPack as MP} from "../../MgvPack.sol";
import "hardhat/console.sol";

contract OfferManager is IMaker, ITaker {
  // erc_addr -> owner_addr -> balance
  AbstractMangrove mgv;
  AbstractMangrove invMgv;
  address caller_id;
  // mgv_addr -> base_addr -> quote_addr -> offerId -> owner
  mapping(address => mapping(address => mapping(address => mapping(uint => address)))) owners;
  uint constant gas_to_execute = 100_000;

  constructor(AbstractMangrove _mgv, AbstractMangrove _inverted) {
    mgv = _mgv;
    invMgv = _inverted;
  }

  //posthook data:
  //outbound_tkn: orp.outbound_tkn,
  // inbound_tkn: orp.inbound_tkn,
  // takerWants: takerWants,
  // takerGives: takerGives,
  // offerId: offerId,
  // offerDeleted: toDelete

  function takerTrade(
    //NB this is not called if mgv is not a flashTaker mgv
    address base,
    address quote,
    uint netReceived,
    uint shouldGive
  ) external override {
    if (msg.sender == address(invMgv)) {
      ITaker(caller_id).takerTrade(base, quote, netReceived, shouldGive); // taker will find funds
      IERC20(quote).transferFrom(caller_id, address(this), shouldGive); // ready to be withdawn by Mangrove
    }
  }

  function makerPosthook(
    ML.SingleOrder calldata _order,
    ML.OrderResult calldata
  ) external override {
    if (msg.sender == address(invMgv)) {
      //should have received funds by now
      address owner = owners[msg.sender][_order.outbound_tkn][
        _order.inbound_tkn
      ][_order.offerId];
      require(owner != address(0), "Unkown owner");
      IERC20(_order.inbound_tkn).transfer(owner, _order.gives);
    }
  }

  // Maker side execute for residual offer
  event Execute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  function makerExecute(ML.SingleOrder calldata _order)
    external
    override
    returns (bytes32 ret)
  {
    emit Execute(
      msg.sender,
      _order.outbound_tkn,
      _order.inbound_tkn,
      _order.offerId,
      _order.wants,
      _order.gives
    );
    bool inverted;
    address MGV;
    if (msg.sender == address(mgv)) {
      MGV = address(mgv);
    }
    if (msg.sender == address(invMgv)) {
      MGV = address(invMgv);
      inverted = true;
    }
    require(MGV != address(0), "Unauth call");
    // if residual of offerId is < dust, offer will be removed and dust lost
    // also freeWeil[this] will increase, offerManager may chose to give it back to owner
    address owner = owners[address(MGV)][_order.outbound_tkn][
      _order.inbound_tkn
    ][_order.offerId];
    console.log(owner);
    if (owner == address(0)) {
      ret = "mgvOffer/unknownOwner";
    }
    if (!inverted) {
      try IERC20(_order.inbound_tkn).transfer(owner, _order.gives) {
        console.log("Success");
        ret = "";
      } catch Error(string memory message) {
        console.log(message);
        ret = "mgvOffer/transferToOwnerFail";
      }
    } else {
      ret = "";
    }
  }

  //marketOrder (base,quote) + NewOffer(quote,base)
  function order(
    AbstractMangrove MGV,
    address base,
    address quote,
    uint wants,
    uint gives,
    bool invertedResidual
  ) external payable {
    bool flashTaker = (address(MGV) == address(invMgv));
    caller_id = msg.sender; // this should come with a reentrancy lock
    if (!flashTaker) {
      // else caller_id will be called when takerTrade is called by Mangrove
      IERC20(quote).transferFrom(msg.sender, address(this), gives); // OfferManager must be approved by sender
    }
    IERC20(quote).approve(address(MGV), 100 ether); // to pay maker
    IERC20(base).approve(address(MGV), 100 ether); // takerfee

    (uint netReceived, ) = MGV.marketOrder(base, quote, wants, gives, true); // OfferManager might collect provisions of failing offers

    try IERC20(base).transfer(msg.sender, netReceived) {
      uint residual_w = wants - netReceived;
      uint residual_g = (gives * residual_w) / wants;

      AbstractMangrove _MGV;
      if (invertedResidual) {
        _MGV = invMgv;
      } else {
        _MGV = mgv;
      }
      (bytes32 config, ) = _MGV.config(base, quote);
      require(
        msg.value >=
          gas_to_execute * uint(MP.global_unpack_gasprice(config)) * 10**9,
        "Insufficent funds to delegate order"
      ); //not checking overflow issues
      (bool success, ) = address(_MGV).call{value: msg.value}("");
      require(success, "provision mgv failed");
      uint residual_ofr = _MGV.newOffer(
        quote,
        base,
        residual_w,
        residual_g,
        gas_to_execute,
        0,
        0
      );
      owners[address(_MGV)][quote][base][residual_ofr] = msg.sender;
    } catch {
      require(false, "Failed to send market order money to owner");
    }
  }
}
