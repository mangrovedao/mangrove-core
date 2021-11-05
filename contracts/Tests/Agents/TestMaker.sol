// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./Passthrough.sol";
import "../../AbstractMangrove.sol";
import "../../MgvPack.sol";
import "hardhat/console.sol";
import {IERC20, IMaker} from "../../MgvLib.sol";
import {Test as TestEvents} from "@giry/hardhat-test-solidity/test.sol";

contract TestMaker is IMaker, Passthrough {
  AbstractMangrove _mgv;
  address _base;
  address _quote;
  bool _shouldFail; // will set mgv allowance to 0
  bool _shouldAbort; // will not return bytes32("")
  bool _shouldRevert; // will revert
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
  ) external virtual override {
    order; //shh
    if (_shouldFailHook) {
      bytes32[1] memory refuse_msg = [bytes32("posthookFail")];
      assembly {
        revert(refuse_msg, 32)
      }
    }

    if (_expectedStatus != bytes32("")) {
      TestEvents.eq(
        result.mgvData,
        _expectedStatus,
        "Incorrect status message"
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

  function updateOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint offerId
  ) public {
    _mgv.updateOffer(_base, _quote, wants, gives, gasreq, 0, pivotId, offerId);
  }

  function retractOffer(uint offerId) public {
    _mgv.retractOffer(_base, _quote, offerId, false);
  }

  function retractOfferWithDeprovision(uint offerId) public {
    _mgv.retractOffer(_base, _quote, offerId, true);
  }

  function provisionMgv(uint amount) public {
    _mgv.fund{value: amount}(address(this));
  }

  function withdrawMgv(uint amount) public returns (bool) {
    return _mgv.withdraw(amount);
  }

  function freeWei() public view returns (uint) {
    return _mgv.balanceOf(address(this));
  }
}
