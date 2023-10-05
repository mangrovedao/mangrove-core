// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "@mgv/src/IMangrove.sol";
import "@mgv/src/core/MgvLib.sol";
import {Test} from "@mgv/forge-std/Test.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

contract TrivialTestMaker is IMaker {
  function makerExecute(MgvLib.SingleOrder calldata) external virtual returns (bytes32) {
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) external virtual {}
}

// could add offer-specific posthookShouldRevert/posthookReturnData here if needed
struct OfferData {
  bool shouldRevert;
  string executeData;
}

contract SimpleTestMaker is TrivialTestMaker {
  IMangrove public mgv;
  OLKey olKey;
  bool _shouldFail; // will set mgv allowance to 0
  bool _shouldRevert; // will revert
  bool _shouldRevertOnNonZeroGives; // will revert if makerGives > 0
  bool _shouldRepost; // will try to repost offer with identical parameters
  bytes32 expectedStatus;
  address tradeCallbackContract; // the `tradeCallback` will be called on this contract during makerExecute
  bytes tradeCallback;
  address posthookNoArgCallbackContract; // the `posthookNoArgCallback` will be called on this contract during makerPosthook with no arguments
  bytes posthookNoArgCallback;
  address posthookCallbackContract; // the `posthookCallbackSelector` will be called on this contract during makerPosthook
  bytes4 posthookCallbackSelector; // this function must take two arguments of type `MgvLib.SingleOrder`
  address executeCallbackContract; // the `executeCallbackSelector` will be called on this contract during makerExecute
  bytes4 executeCallbackSelector; // this function must take a single argument of type `MgvLib.SingleOrder`
  ///@notice stores parameters for each posted offer
  ///@notice overrides global @shouldFail/shouldReturn if true

  mapping(bytes32 => mapping(uint => OfferData)) offerDatas;

  ///@notice stores whether makerExecute was called for an offer.
  ///@notice Only usable when makerExecute does not revert
  mapping(bytes32 => mapping(uint => bool)) offersExecuted;

  ///@notice stores whether makerPosthook was called for an offer.
  ///@notice Only usable when makerPosthook does not revert
  mapping(bytes32 => mapping(uint => bool)) offersPosthookExecuted;

  constructor(IMangrove _mgv, OLKey memory _ol) {
    mgv = _mgv;
    olKey = _ol;
  }

  receive() external payable {}

  event Execute(
    address mgv, address base, address quote, uint tickSpacing, uint offerId, uint takerWants, uint takerGives
  );

  function logExecute(address _mgv, OLKey calldata _ol, uint offerId, uint takerWants, uint takerGives) external {
    emit Execute(_mgv, _ol.outbound_tkn, _ol.inbound_tkn, _ol.tickSpacing, offerId, takerWants, takerGives);
  }

  function makerExecuteWasCalled(uint offerId) external view returns (bool) {
    return makerExecuteWasCalled(olKey, offerId);
  }

  function makerExecuteWasCalled(OLKey memory _olKey, uint offerId) public view returns (bool) {
    return offersExecuted[_olKey.hash()][offerId];
  }

  function makerPosthookWasCalled(uint offerId) external view returns (bool) {
    return makerPosthookWasCalled(olKey, offerId);
  }

  function makerPosthookWasCalled(OLKey memory _olKey, uint offerId) public view returns (bool) {
    return offersPosthookExecuted[_olKey.hash()][offerId];
  }

  function setExecuteCallback(address _executeCallbackContract, bytes4 _executeCallbackSelector) external {
    executeCallbackContract = _executeCallbackContract;
    executeCallbackSelector = _executeCallbackSelector;
  }

  function setTradeCallback(address _tradeCallbackContract, bytes calldata _tradeCallback) external {
    tradeCallbackContract = _tradeCallbackContract;
    tradeCallback = _tradeCallback;
  }

  function setPosthookNoArgCallback(address _posthookNoArgCallbackContract, bytes calldata _posthookNoArgCallback)
    external
  {
    posthookNoArgCallbackContract = _posthookNoArgCallbackContract;
    posthookNoArgCallback = _posthookNoArgCallback;
  }

  function setPosthookCallback(address _posthookCallbackContract, bytes4 _posthookCallbackSelector) external {
    posthookCallbackContract = _posthookCallbackContract;
    posthookCallbackSelector = _posthookCallbackSelector;
  }

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function shouldRevertOnNonZeroGives(bool should) external {
    _shouldRevertOnNonZeroGives = should;
  }

  function shouldFail(bool should) external {
    _shouldFail = should;
  }

  function shouldRepost(bool should) external {
    _shouldRepost = should;
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
    offersExecuted[order.olKey.hash()][order.offerId] = true;
    if (executeCallbackContract != address(0) && executeCallbackSelector.length > 0) {
      (bool success,) = executeCallbackContract.call(abi.encodeWithSelector(executeCallbackSelector, (order)));
      require(success, "makerExecute executeCallback must work");
    }

    if (_shouldRevert) {
      revert("testMaker/shouldRevert");
    }

    if (_shouldRevertOnNonZeroGives && order.takerGives > 0) {
      revert("testMaker/shouldRevertOnNonZeroGives");
    }

    OfferData memory offerData = offerDatas[order.olKey.hash()][order.offerId];

    if (offerData.shouldRevert) {
      revert(offerData.executeData);
    }

    if (_shouldFail) {
      TransferLib.approveToken(IERC20(order.olKey.outbound_tkn), address(mgv), 0);
    }

    if (tradeCallbackContract != address(0) && tradeCallback.length > 0) {
      (bool success,) = tradeCallbackContract.call(tradeCallback);
      require(success, "makerExecute tradeCallback must work");
    }

    emit Execute(
      msg.sender,
      order.olKey.outbound_tkn,
      order.olKey.inbound_tkn,
      order.olKey.tickSpacing,
      order.offerId,
      order.takerWants,
      order.takerGives
    );

    return bytes32(bytes(offerData.executeData));
  }

  bool _shouldFailHook;

  function setShouldFailHook(bool should) external {
    _shouldFailHook = should;
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) public virtual override {
    offersPosthookExecuted[order.olKey.hash()][order.offerId] = true;
    order; //shh
    result; //shh
    if (_shouldFailHook) {
      revert("posthookFail");
    }

    if (posthookCallbackContract != address(0) && posthookCallbackSelector.length > 0) {
      (bool success,) = posthookCallbackContract.call(abi.encodeWithSelector(posthookCallbackSelector, (order)));
      require(success, "makerPosthook posthookCallback must work");
    }

    if (posthookNoArgCallbackContract != address(0) && posthookNoArgCallback.length > 0) {
      (bool success,) = posthookNoArgCallbackContract.call(posthookNoArgCallback);
      require(success, "makerPosthook posthookNoArgCallback must work");
    }

    if (_shouldRepost) {
      mgv.updateOfferByVolume(
        order.olKey, order.offer.wants(), order.offer.gives(), order.offerDetail.gasreq(), 0, order.offerId
      );
    }
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq) public returns (uint) {
    return newOfferByVolume(olKey, wants, gives, gasreq);
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq, OfferData memory offerData) public returns (uint) {
    return newOfferByVolume(olKey, wants, gives, gasreq, offerData);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint amount) public returns (uint) {
    return newOfferByVolumeWithFunding(olKey, wants, gives, gasreq, 0, amount);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint amount, OfferData memory offerData)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(olKey, wants, gives, gasreq, 0, amount, offerData);
  }

  function newOfferByVolumeWithFunding(uint wants, uint gives, uint gasreq, uint gasprice, uint amount)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(olKey, wants, gives, gasreq, gasprice, amount);
  }

  function newOfferByVolume(OLKey memory _ol, uint wants, uint gives, uint gasreq) public returns (uint) {
    OfferData memory offerData;
    return newOfferByVolume(_ol, wants, gives, gasreq, offerData);
  }

  function newOfferByVolume(OLKey memory _ol, uint wants, uint gives, uint gasreq, OfferData memory offerData)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(_ol, wants, gives, gasreq, 0, 0, offerData);
  }

  function newOfferByVolumeWithFunding(OLKey memory _ol, uint wants, uint gives, uint gasreq, uint amount)
    public
    returns (uint)
  {
    return newOfferByVolumeWithFunding(_ol, wants, gives, gasreq, 0, amount);
  }

  function newOfferByVolumeWithFunding(
    OLKey memory _ol,
    uint wants,
    uint gives,
    uint gasreq,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    return newOfferByVolumeWithFunding(_ol, wants, gives, gasreq, 0, amount, offerData);
  }

  function newOfferByVolume(uint wants, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByVolumeWithFunding(olKey, wants, gives, gasreq, gasprice, 0);
  }

  function newOfferByVolumeWithFunding(
    OLKey memory _ol,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount
  ) public returns (uint) {
    OfferData memory offerData;
    return newOfferByVolumeWithFunding(_ol, wants, gives, gasreq, gasprice, amount, offerData);
  }

  function newOfferByVolumeWithFunding(
    OLKey memory _ol,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    uint offerId = mgv.newOfferByVolume{value: amount}(_ol, wants, gives, gasreq, gasprice);
    offerDatas[_ol.hash()][offerId] = offerData;
    return offerId;
  }

  function newOfferByTick(Tick tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTick(tick, gives, gasreq, 0);
  }

  function newFailingOfferByTick(Tick tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTickWithFunding(
      olKey, tick, gives, gasreq, 0, 0, OfferData({shouldRevert: true, executeData: "someData"})
    );
  }

  function newOfferByTick(Tick tick, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByTick(olKey, tick, gives, gasreq, gasprice);
  }

  function newOfferByTick(OLKey memory _olKey, Tick tick, uint gives, uint gasreq) public returns (uint) {
    return newOfferByTick(_olKey, tick, gives, gasreq, 0);
  }

  function newOfferByTick(OLKey memory _olKey, Tick tick, uint gives, uint gasreq, uint gasprice) public returns (uint) {
    return newOfferByTickWithFunding(_olKey, tick, gives, gasreq, gasprice, 0);
  }

  function newOfferByTickWithFunding(OLKey memory _ol, Tick tick, uint gives, uint gasreq, uint gasprice, uint amount)
    public
    returns (uint)
  {
    OfferData memory offerData;
    return newOfferByTickWithFunding(_ol, tick, gives, gasreq, gasprice, amount, offerData);
  }

  function newOfferByTickWithFunding(
    OLKey memory _ol,
    Tick tick,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint amount,
    OfferData memory offerData
  ) public returns (uint) {
    uint offerId = mgv.newOfferByTick{value: amount}(_ol, tick, gives, gasreq, gasprice);
    offerDatas[olKey.hash()][offerId] = offerData;
    return offerId;
  }

  function updateOfferByTick(Tick tick, uint gives, uint gasreq, uint offerId) public {
    updateOfferByTick(tick, gives, gasreq, 0, offerId);
  }

  function updateOfferByTick(Tick tick, uint gives, uint gasreq, uint gasprice, uint offerId) public {
    OfferData memory offerData;
    updateOfferByTickWithFunding(olKey, tick, gives, gasreq, gasprice, offerId, 0, offerData);
  }

  function updateOfferByTickWithFunding(
    OLKey memory _olKey,
    Tick tick,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint offerId,
    uint amount,
    OfferData memory offerData
  ) public {
    mgv.updateOfferByTick{value: amount}(_olKey, tick, gives, gasreq, gasprice, offerId);
    offerDatas[_olKey.hash()][offerId] = offerData;
  }

  function updateOfferByVolume(uint wants, uint gives, uint gasreq, uint offerId, OfferData memory offerData) public {
    updateOfferByVolumeWithFunding(wants, gives, gasreq, offerId, 0, offerData);
  }

  function updateOfferByVolume(uint wants, uint gives, uint gasreq, uint offerId) public {
    updateOfferByVolume(olKey, wants, gives, gasreq, offerId);
  }

  function updateOfferByVolume(OLKey memory _olKey, uint wants, uint gives, uint gasreq, uint offerId) public {
    OfferData memory offerData;
    updateOfferByVolumeWithFunding(_olKey, wants, gives, gasreq, offerId, 0, offerData);
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
    updateOfferByVolumeWithFunding(olKey, wants, gives, gasreq, offerId, amount, offerData);
    offerDatas[olKey.hash()][offerId] = offerData;
  }

  function updateOfferByVolumeWithFunding(
    OLKey memory _olKey,
    uint wants,
    uint gives,
    uint gasreq,
    uint offerId,
    uint amount,
    OfferData memory offerData
  ) public {
    mgv.updateOfferByVolume{value: amount}(_olKey, wants, gives, gasreq, 0, offerId);
    offerDatas[_olKey.hash()][offerId] = offerData;
  }

  function retractOffer(uint offerId) public returns (uint) {
    return retractOffer(olKey, offerId);
  }

  function retractOffer(OLKey memory _olKey, uint offerId) public returns (uint) {
    return mgv.retractOffer(_olKey, offerId, false);
  }

  function retractOfferWithDeprovision(uint offerId) public returns (uint) {
    return mgv.retractOffer(olKey, offerId, true);
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
    return marketOrderByVolume(olKey, takerWants, takerGives);
  }

  function marketOrderByVolume(OLKey memory _olKey, uint takerWants, uint takerGives)
    public
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(_olKey, takerWants, takerGives, true);
  }

  function clean(uint offerId, uint takerWants) public returns (bool success) {
    Tick tick = mgv.offers(olKey, offerId).tick();
    return clean(olKey, offerId, tick, takerWants);
  }

  function clean(uint offerId, Tick tick, uint takerWants) public returns (bool success) {
    return clean(olKey, offerId, tick, takerWants);
  }

  function clean(OLKey memory _olKey, uint offerId, uint takerWants) public returns (bool success) {
    Tick tick = mgv.offers(olKey, offerId).tick();
    return clean(_olKey, offerId, tick, takerWants);
  }

  function clean(OLKey memory _olKey, uint offerId, Tick tick, uint takerWants) public returns (bool success) {
    MgvLib.CleanTarget[] memory targets = new MgvLib.CleanTarget[](1);
    targets[0] = MgvLib.CleanTarget(offerId, tick, type(uint48).max, takerWants);
    (uint successes,) = mgv.cleanByImpersonation(_olKey, targets, address(this));
    return successes > 0;
  }
}

contract TestMaker is SimpleTestMaker, Test {
  constructor(IMangrove mgv, OLKey memory _ol) SimpleTestMaker(mgv, _ol) {}

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) public virtual override {
    if (expectedStatus != bytes32("")) {
      assertEq(result.mgvData, expectedStatus, "Incorrect status message");
    }
    super.makerPosthook(order, result);
  }
}
