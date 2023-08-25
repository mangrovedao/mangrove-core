// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {TestTaker} from "mgv_test/lib/agents/TestTaker.sol";
import {IMaker, MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {console2 as console} from "forge-std/console2.sol";

contract TooDeepRecursionClogTest is MangroveTest, IMaker {
  bool internal shouldFail = false;

  TestTaker internal taker;
  uint internal minVolume;
  uint internal gasreq = 100_000;
  uint internal gaslimit = 10_000_000;

  // Fail for second order within same market order - flag is reset on the way out in posthook
  function makerExecute(MgvLib.SingleOrder calldata) public virtual override returns (bytes32 result) {
    result = bytes32(0);
    if (shouldFail) {
      revert("AH AH AH!");
    } else {
      shouldFail = true;
    }
  }

  // Resets failure flag and reposts offer at same price.
  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) external override {
    shouldFail = false;
    try mgv.updateOfferByTick(
      address(order.outbound_tkn), address(order.inbound_tkn), 0, minVolume, gasreq, 0, order.offerId
    ) {
      // we do not fail if we cannot repost since we still need to set shouldFail to false.
    } catch {}
  }

  function setUp() public virtual override {
    super.setUp();

    // Some taker
    taker = setupTaker($(base), $(quote), "Taker");
    deal($(quote), address(taker), 1 ether);
    taker.approveMgv(quote, 1 ether);

    deal($(base), $(this), 5 ether);
    minVolume = reader.minVolume($(base), $(quote), gasreq);

    // 100 offers at same price at minimum volume.
    for (uint i; i < 100; ++i) {
      mgv.newOfferByTick($(base), $(quote), 0, minVolume, gasreq, 0);
    }
  }

  function takeSome(uint wants) internal {
    (uint takerGot,) = taker.marketOrder{gas: gaslimit}(0, wants, false);
    assertGt(takerGot, 0, "Taker should get something");
  }

  function test_take_one_succeeds() public {
    // Taking one offer should succeed as it is just a single successful offer.
    takeSome(minVolume);
  }

  function test_take_two_successively_succeeds() public {
    // Taking two offers successfully should succeed as each is just a single successful offer.
    takeSome(minVolume);
    takeSome(minVolume);
  }

  function test_take_more_than_first_succeeds() public {
    // Taking more volume than the first offer delivers should succeed but will not deliver the full volume since only
    // the first offer succeeds. All other offer fails.
    takeSome(minVolume + 1);
  }

  function test_take_one_then_two_at_once_succeeds() public {
    // Same as test_take_more_than_first_succeeds, but verifies that the clog persists after a successful order.
    takeSome(minVolume);
    takeSome(minVolume + 1);
  }

  function testFail_take_more_than_first_fails_for_deep_stack() public {
    mgv.setMaxRecursionDepth(100);
    gaslimit = 200_000_000;
    // Taking more volume than the first offer delivers should succeed but will not deliver the full volume since only
    // the first offer succeeds. All other offer fails.
    takeSome(minVolume + 1);
  }

  function testFail_take_one_then_two_at_once_fails_for_deep_stack() public {
    mgv.setMaxRecursionDepth(100);
    gaslimit = 200_000_000;
    // Same as testFail_take_more_than_first_fails_for_deep_stack, but verifies that the clog persists after a successful order.
    takeSome(minVolume);
    takeSome(minVolume + 1);
  }
}

contract TooMuchGasClogTest is TooDeepRecursionClogTest {
  function setUp() public override {
    gasreq = 2_000_000;
    super.setUp();
  }

  function makerExecute(MgvLib.SingleOrder calldata order) public override returns (bytes32 result) {
    // Burn gas, but leave enough for super and posthook.
    uint i;
    while (gasleft() > 100_000) {
      i++;
    }
    return super.makerExecute(order);
  }
}
