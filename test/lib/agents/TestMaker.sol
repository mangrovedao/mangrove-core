// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "mgv_src/AbstractMangrove.sol";
import {IERC20, MgvLib, IMaker} from "mgv_src/MgvLib.sol";
import {Test} from "forge-std/Test.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

contract TrivialTestMaker is IMaker {
  function makerExecute(MgvLib.SingleOrder calldata) external virtual returns (bytes32) {
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) external virtual {}
}

//TODO add posthookShouldRevert/posthookReturnData
struct OfferData {
  bool shouldRevert;
  string executeData;
}

contract SimpleTestMaker is TrivialTestMaker {
  AbstractMangrove public mgv;
  address public base;
  address public quote;
  bool shouldFail_; // will set mgv allowance to 0
  bool shouldRevert_; // will revert
  bool shouldRepost_; // will try to repost offer with identical parameters
  bytes32 expectedStatus;
  ///@notice stores parameters for each posted offer
  ///@notice overrides global @shouldFail/shouldReturn if true

  mapping(address => mapping(address => mapping(uint => OfferData))) offerDatas;

  constructor(AbstractMangrove _mgv, IERC20 _base, IERC20 _quote) {
    mgv = _mgv;
    base = address(_base);
    quote = address(_quote);
  }

  receive() external payable {}

  event Execute(address mgv, address base, address quote, uint offerId, uint takerWants, uint takerGives);

  function logExecute(address _mgv, address _base, address _quote, uint offerId, uint takerWants, uint takerGives)
    external
  {
    emit Execute(_mgv, _base, _quote, offerId, takerWants, takerGives);
  }

  function shouldRevert(bool should) external {
    shouldRevert_ = should;
  }

  function shouldFail(bool should) external {
    shouldFail_ = should;
  }

  function shouldRepost(bool should) external {
    shouldRepost_ = should;
  }

  function approveMgv(IERC20 token, uint amount) public {
    TransferLib.approveToken(token, address(mgv), amount);
  }

  function expect(bytes32 mgvData) external {
    expectedStatus = mgvData;
  }

  function transferToken(IERC20 token, address to, uint amount) external {
    TransferLib.transferToken(token, to, amount);
  }

  function makerExecute(MgvLib.SingleOrder calldata order) public virtual override returns (bytes32) {
    if (shouldRevert_) {
      revert("testMaker/shouldRevert");
    }

    OfferData memory offerData = offerDatas[order.outbound_tkn][order.inbound_tkn][order.offerId];

    if (offerData.shouldRevert) {
      revert(offerData.executeData);
    }

    if (shouldFail_) {
      TransferLib.approveToken(IERC20(order.outbound_tkn), address(mgv), 0);
    }

    emit Execute(msg.sender, order.outbound_tkn, order.inbound_tkn, order.offerId, order.wants, order.gives);

    return bytes32(bytes(offerData.executeData));
  }

  bool _shouldFailHook;

  function setShouldFailHook(bool should) external {
    _shouldFailHook = should;
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) public virtual override {
    order; //shh
    result; //shh
    if (_shouldFailHook) {
      revert("posthookFail");
    }

    if (shouldRepost_) {
      mgv.updateOfferByVolume(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offer.wants(),
        order.offer.gives(),
        order.offerDetail.gasreq(),
        0,
        order.offerId
      );
    }
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq) public returns (uint) {
    return newOfferByVolume(base, quote, wants, gives, gasreq);
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq, OfferData memory offerData) public returns (uint) {
    return newOfferByVolume(base, quote, wants, gives, gasreq, offerData);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint amount) public returns (uint) {
    return newOfferByVolumeWithFunding(base, quote, wants, gives, gasreq, 0, amount);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint amount, OfferData memory offerData)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(base, quote, wants, gives, gasreq, 0, amount, offerData);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint gasprice, uint amount)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(base, quote, wants, gives, gasreq, gasprice, amount);
  }

  function newOfferByVolume(address _base, address _quote, uint wants, uint gives, uint gasreq) public returns (uint) {
    OfferData memory offerData;
    return newOfferByVolume(_base, _quote, wants, gives, gasreq, offerData);
  }

  function newOfferByVolume(
    address _base,
    address _quote,
    uint wants,
    uint gives,
    uint gasreq,
    OfferData memory offerData
  ) public returns (uint) {
    return newOfferByVolumeWithFunding(_base, _quote, wants, gives, gasreq, 0, 0, offerData);
  }

  function newOfferByVolumeWithFunding(address _base, address _quote, uint wants, uint gives, uint gasreq, uint amount)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(_base, _quote, wants, gives, gasreq, 0, amount);
  }

  function newOfferByVolumeWithFunding(
    address _base,
    address _quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    return newOfferByVolumeWithFunding(_base, _quote, wants, gives, gasreq, 0, amount, offerData);
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByVolumeWithFunding(base, quote, wants, gives, gasreq, gasprice, 0);
  }

  function newOfferByVolumeWithFunding(
    address _base,
    address _quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount
  ) public returns (uint) {
    OfferData memory offerData;
    return newOfferByVolumeWithFunding(_base, _quote, wants, gives, gasreq, gasprice, amount, offerData);
  }

  function newOfferByVolumeWithFunding(
    address _base,
    address _quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    uint offerId = mgv.newOfferByVolume{value: amount}(_base, _quote, wants, gives, gasreq, gasprice);
    offerDatas[_base][_quote][offerId] = offerData;
    return offerId;
  }

  function newOfferByTick(int tick, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByTickWithFunding(base, quote, tick, gives, gasreq, gasprice, 0);
  }

  function newOfferByTickWithFunding(
    address _base,
    address _quote,
    int tick,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount
  ) public returns (uint) {
    OfferData memory offerData;
    return newOfferByTickWithFunding(_base, _quote, tick, gives, gasreq, gasprice, amount, offerData);
  }

  function newOfferByTickWithFunding(
    address _base,
    address _quote,
    int tick,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    uint offerId = mgv.newOfferByTick{value: amount}(_base, _quote, tick, gives, gasreq, gasprice);
    offerDatas[_base][_quote][offerId] = offerData;
    return offerId;
  }

  function updateOfferByVolume(uint wants, uint gives, uint gasreq, uint offerId, OfferData memory offerData) public {
    updateOfferByVolumeWithFunding(wants, gives, gasreq, offerId, 0, offerData);
  }

  function updateOfferByVolume(uint wants, uint gives, uint gasreq, uint offerId) public {
    OfferData memory offerData;
    updateOfferByVolumeWithFunding(wants, gives, gasreq, offerId, 0, offerData);
  }

  function updateOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint offerId, uint amount) public {
    OfferData memory offerData;
    updateOfferByVolumeWithFunding(wants, gives, gasreq, offerId, amount, offerData);
  }

  function updateOfferByVolumeWithFunding(
    uint wants,
    uint gives,
    uint gasreq,
    uint offerId,
    uint amount,
    OfferData memory offerData
  ) public {
    mgv.updateOfferByVolume{value: amount}(base, quote, wants, gives, gasreq, 0, offerId);
    offerDatas[base][quote][offerId] = offerData;
  }

  function retractOffer(uint offerId) public returns (uint) {
    return mgv.retractOffer(base, quote, offerId, false);
  }

  function retractOfferWithDeprovision(uint offerId) public returns (uint) {
    return mgv.retractOffer(base, quote, offerId, true);
  }

  function provisionMgv(uint amount) public payable {
    mgv.fund{value: amount}(address(this));
  }

  function withdrawMgv(uint amount) public returns (bool) {
    return mgv.withdraw(amount);
  }

  function mgvBalance() public view returns (uint) {
    return mgv.balanceOf(address(this));
  }
}

contract TestMaker is SimpleTestMaker, Test {
  constructor(AbstractMangrove mgv, IERC20 base, IERC20 quote) SimpleTestMaker(mgv, base, quote) {}

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) public virtual override {
    if (expectedStatus != bytes32("")) {
      assertEq(result.mgvData, expectedStatus, "Incorrect status message");
    }
    super.makerPosthook(order, result);
  }
}
