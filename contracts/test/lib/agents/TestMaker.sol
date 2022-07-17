// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
pragma abicoder v2;

import "mgv_src/AbstractMangrove.sol";
import {IERC20, MgvLib as ML, P, IMaker} from "mgv_src/MgvLib.sol";
import {Test} from "forge-std/Test.sol";

contract TrivialTestMaker is IMaker {
  function makerExecute(ML.SingleOrder calldata)
    external
    virtual
    returns (bytes32)
  {
    return "";
  }

  function makerPosthook(ML.SingleOrder calldata, ML.OrderResult calldata)
    external
    virtual
  {}
}

contract SimpleTestMaker is TrivialTestMaker {
  AbstractMangrove _mgv;
  address _base;
  address _quote;
  bool _shouldFail; // will set mgv allowance to 0
  bool _shouldAbort; // will not return bytes32("")
  bool _shouldRevert; // will revert
  bool _shouldRepost; // will try to repost offer with identical parameters
  bytes32 _expectedStatus;

  constructor(
    AbstractMangrove mgv,
    IERC20 base,
    IERC20 quote
  ) {
    _mgv = mgv;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  event Execute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  function logExecute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  ) external {
    emit Execute(mgv, base, quote, offerId, takerWants, takerGives);
  }

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function shouldFail(bool should) external {
    _shouldFail = should;
  }

  function shouldAbort(bool should) external {
    _shouldAbort = should;
  }

  function shouldRepost(bool should) external {
    _shouldRepost = should;
  }

  function approveMgv(IERC20 token, uint amount) public {
    token.approve(address(_mgv), amount);
  }

  function expect(bytes32 mgvData) external {
    _expectedStatus = mgvData;
  }

  function transferToken(
    IERC20 token,
    address to,
    uint amount
  ) external {
    token.transfer(to, amount);
  }

  function makerExecute(ML.SingleOrder calldata order)
    public
    virtual
    override
    returns (bytes32)
  {
    if (_shouldRevert) {
      bytes32[1] memory revert_msg = [bytes32("testMaker/revert")];
      assembly {
        revert(revert_msg, 32)
      }
    }
    emit Execute(
      msg.sender,
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId,
      order.wants,
      order.gives
    );
    if (_shouldFail) {
      IERC20(order.outbound_tkn).approve(address(_mgv), 0);
      // bytes32[1] memory refuse_msg = [bytes32("testMaker/transferFail")];
      // assembly {
      //   return(refuse_msg, 32)
      // }
      //revert("testMaker/fail");
    }
    if (_shouldAbort) {
      return "abort";
    } else {
      return "";
    }
  }

  bool _shouldFailHook;

  function setShouldFailHook(bool should) external {
    _shouldFailHook = should;
  }

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) public virtual override {
    order; //shh
    result; //shh
    if (_shouldFailHook) {
      revert("posthookFail");
    }

    if (_shouldRepost) {
      _mgv.updateOffer(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offer.wants(),
        order.offer.gives(),
        order.offerDetail.gasreq(),
        0,
        order.offer.prev(),
        order.offerId
      );
    }
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_mgv.newOffer(_base, _quote, wants, gives, gasreq, 0, pivotId));
  }

  function newOfferWithFunding(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint amount
  ) public returns (uint) {
    return (
      _mgv.newOffer{value: amount}(
        _base,
        _quote,
        wants,
        gives,
        gasreq,
        0,
        pivotId
      )
    );
  }

  function newOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId));
  }

  function newOfferWithFunding(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint amount
  ) public returns (uint) {
    return (
      _mgv.newOffer{value: amount}(
        base,
        quote,
        wants,
        gives,
        gasreq,
        0,
        pivotId
      )
    );
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public returns (uint) {
    return (
      _mgv.newOffer(_base, _quote, wants, gives, gasreq, gasprice, pivotId)
    );
  }

  function newOfferWithFunding(
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint amount
  ) public returns (uint) {
    return (
      _mgv.newOffer{value: amount}(
        _base,
        _quote,
        wants,
        gives,
        gasreq,
        gasprice,
        pivotId
      )
    );
  }

  function updateOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint offerId
  ) public {
    _mgv.updateOffer(_base, _quote, wants, gives, gasreq, 0, pivotId, offerId);
  }

  function updateOfferWithFunding(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint offerId,
    uint amount
  ) public {
    _mgv.updateOffer{value: amount}(
      _base,
      _quote,
      wants,
      gives,
      gasreq,
      0,
      pivotId,
      offerId
    );
  }

  function retractOffer(uint offerId) public returns (uint) {
    return _mgv.retractOffer(_base, _quote, offerId, false);
  }

  function retractOfferWithDeprovision(uint offerId) public returns (uint) {
    return _mgv.retractOffer(_base, _quote, offerId, true);
  }

  function provisionMgv(uint amount) public {
    _mgv.fund{value: amount}(address(this));
  }

  function withdrawMgv(uint amount) public returns (bool) {
    return _mgv.withdraw(amount);
  }

  function mgvBalance() public view returns (uint) {
    return _mgv.balanceOf(address(this));
  }
}

contract TestMaker is SimpleTestMaker, Test {
  constructor(
    AbstractMangrove mgv,
    IERC20 base,
    IERC20 quote
  ) SimpleTestMaker(mgv, base, quote) {}

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) public virtual override {
    if (_expectedStatus != bytes32("")) {
      assertEq(result.mgvData, _expectedStatus, "Incorrect status message");
    }
    super.makerPosthook(order, result);
  }
}
