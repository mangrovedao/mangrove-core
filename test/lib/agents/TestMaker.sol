// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "mgv_src/AbstractMangrove.sol";
import {IERC20, MgvLib, IMaker} from "mgv_src/MgvLib.sol";
import {Test} from "forge-std/Test.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {Tick} from "mgv_lib/TickLib.sol";

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

contract SimpleTestMaker is TrivialTestMaker, Script2 {
  AbstractMangrove public mgv;
  address public base;
  address public quote;
  bool shouldFail_; // will set mgv allowance to 0
  bool shouldRevert_; // will revert
  bool shouldRevertOnNonZeroGives_; // will revert if makerGives > 0
  bool shouldRepost_; // will try to repost offer with identical parameters
  bytes32 expectedStatus;
  address tradeCallbackContract; // the `tradeCallback` will be called on this contract during makerExecute
  bytes tradeCallback;
  address posthookCallbackContract; // the `posthookCallback` will be called on this contract during makerExecute
  bytes posthookCallback;
  ///@notice stores parameters for each posted offer
  ///@notice overrides global @shouldFail/shouldReturn if true

  mapping(address => mapping(address => mapping(uint => OfferData))) offerDatas;

  ///@notice stores whether makerExecute was called for an offer.
  ///@notice Only usable when makerExecute does not revert
  mapping(address => mapping(address => mapping(uint => bool))) offersExecuted;

  ///@notice stores whether makerPosthook was called for an offer.
  ///@notice Only usable when makerPosthook does not revert
  mapping(address => mapping(address => mapping(uint => bool))) offersPosthookExecuted;

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

  function makerExecuteWasCalled(uint offerId) external view returns (bool) {
    return makerExecuteWasCalled(base, quote, offerId);
  }

  function makerExecuteWasCalled(address _base, address _quote, uint offerId) public view returns (bool) {
    return offersExecuted[_base][_quote][offerId];
  }

  function makerPosthookWasCalled(uint offerId) external view returns (bool) {
    return makerPosthookWasCalled(base, quote, offerId);
  }

  function makerPosthookWasCalled(address _base, address _quote, uint offerId) public view returns (bool) {
    return offersPosthookExecuted[_base][_quote][offerId];
  }

  function setTradeCallback(address _tradeCallbackContract, bytes calldata _tradeCallback) external {
    tradeCallbackContract = _tradeCallbackContract;
    tradeCallback = _tradeCallback;
  }

  function setPosthookCallback(address _posthookCallbackContract, bytes calldata _posthookCallback) external {
    posthookCallbackContract = _posthookCallbackContract;
    posthookCallback = _posthookCallback;
  }

  function shouldRevert(bool should) external {
    shouldRevert_ = should;
  }

  function shouldRevertOnNonZeroGives(bool should) external {
    shouldRevertOnNonZeroGives_ = should;
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
    offersExecuted[order.outbound_tkn][order.inbound_tkn][order.offerId] = true;

    if (shouldRevert_) {
      revert("testMaker/shouldRevert");
    }

    if (shouldRevertOnNonZeroGives_ && order.gives > 0) {
      revert("testMaker/shouldRevertOnNonZeroGives");
    }

    OfferData memory offerData = offerDatas[order.outbound_tkn][order.inbound_tkn][order.offerId];

    if (offerData.shouldRevert) {
      revert(offerData.executeData);
    }

    if (shouldFail_) {
      TransferLib.approveToken(IERC20(order.outbound_tkn), address(mgv), 0);
    }

    if (tradeCallbackContract != address(0) && tradeCallback.length > 0) {
      (bool success,) = tradeCallbackContract.call(tradeCallback);
      require(success, "makerExecute tradeCallback must work");
    }

    emit Execute(msg.sender, order.outbound_tkn, order.inbound_tkn, order.offerId, order.wants, order.gives);

    return bytes32(bytes(offerData.executeData));
  }

  bool _shouldFailHook;

  function setShouldFailHook(bool should) external {
    _shouldFailHook = should;
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) public virtual override {
    offersPosthookExecuted[order.outbound_tkn][order.inbound_tkn][order.offerId] = true;
    order; //shh
    result; //shh
    if (_shouldFailHook) {
      revert("posthookFail");
    }

    if (posthookCallbackContract != address(0) && posthookCallback.length > 0) {
      (bool success,) = posthookCallbackContract.call(posthookCallback);
      require(success, "makerExecute posthookCallback must work");
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

  function newOfferByTick(int tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTick(tick, gives, gasreq, 0);
  }

  function newFailingOfferByTick(int tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTickWithFunding(
      base, quote, tick, gives, gasreq, 0, 0, OfferData({shouldRevert: true, executeData: "someData"})
    );
  }

  function newOfferByTick(int tick, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByTick(base, quote, tick, gives, gasreq, gasprice);
  }

  function newOfferByTick(address _base, address _quote, int tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTick(_base, _quote, tick, gives, gasreq, 0);
  }

  function newOfferByTick(address _base, address _quote, int tick, uint gives, uint gasreq, uint gasprice)
    public
    returns (uint)
  {
    return newOfferByTickWithFunding(_base, _quote, tick, gives, gasreq, gasprice, 0);
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
    updateOfferByVolume(base, quote, wants, gives, gasreq, offerId);
  }

  function updateOfferByVolume(address _base, address _quote, uint wants, uint gives, uint gasreq, uint offerId) public {
    OfferData memory offerData;
    updateOfferByVolumeWithFunding(_base, _quote, wants, gives, gasreq, offerId, 0, offerData);
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
    updateOfferByVolumeWithFunding(base, quote, wants, gives, gasreq, offerId, amount, offerData);
  }

  function updateOfferByVolumeWithFunding(
    address _base,
    address _quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint offerId,
    uint amount,
    OfferData memory offerData
  ) public {
    mgv.updateOfferByVolume{value: amount}(_base, _quote, wants, gives, gasreq, 0, offerId);
    offerDatas[base][quote][offerId] = offerData;
  }

  function retractOffer(uint offerId) public returns (uint) {
    return retractOffer(base, quote, offerId);
  }

  function retractOffer(address _base, address _quote, uint offerId) public returns (uint) {
    return mgv.retractOffer(_base, _quote, offerId, false);
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

  // Taker functions
  function marketOrderByVolume(uint takerWants, uint takerGives) public returns (uint takerGot, uint takerGave) {
    return marketOrderByVolume(base, quote, takerWants, takerGives);
  }

  function marketOrderByVolume(address _base, address _quote, uint takerWants, uint takerGives)
    public
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(_base, _quote, takerWants, takerGives, true);
  }

  function clean(uint offerId, uint takerWants) public returns (bool success) {
    return clean(base, quote, offerId, takerWants);
  }

  function clean(address _base, address _quote, uint offerId, uint takerWants) public returns (bool success) {
    Tick tick = mgv.offers(_base, _quote, offerId).tick();
    (uint successes,) = mgv.cleanByImpersonation(
      _base,
      _quote,
      wrap_dynamic(MgvLib.CleanTarget(offerId, Tick.unwrap(tick), type(uint48).max, takerWants)),
      address(this)
    );
    return successes > 0;
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
