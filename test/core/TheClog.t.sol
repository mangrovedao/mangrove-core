// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "@mgv/test/lib/MangroveTest.sol";
import {TestTaker} from "@mgv/test/lib/agents/TestTaker.sol";
import "@mgv/src/core/MgvLib.sol";
import {console2 as console} from "@mgv/forge-std/console2.sol";

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
    try mgv.updateOfferByTick(order.olKey, Tick.wrap(0), minVolume, gasreq, 0, order.offerId) {
      // we do not fail if we cannot repost since we still need to set shouldFail to false.
    } catch {}
  }

  function setUp() public virtual override {
    super.setUp();

    // Some taker
    taker = setupTaker(olKey, "Taker");
    deal($(quote), address(taker), 1 ether);
    taker.approveMgv(quote, 1 ether);

    deal($(base), $(this), 5 ether);
    minVolume = reader.minVolume(olKey, gasreq);

    // 100 offers at same price at minimum volume.
    for (uint i; i < 100; ++i) {
      mgv.newOfferByTick(olKey, Tick.wrap(0), minVolume, gasreq, 0);
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

  function test_take_more_than_first_fails_for_deep_stack() public {
    mgv.setMaxRecursionDepth(100);
    gaslimit = 200_000_000;
    // Taking more volume than the first offer delivers should succeed but will not deliver the full volume since only
    // the first offer succeeds. All other offer fails.
    vm.expectRevert();
    vm.prank($(taker));
    mgv.marketOrderByTickCustom(olKey, Tick.wrap(MAX_TICK), minVolume + 1, false, type(uint).max);
  }

  function test_take_one_then_two_at_once_fails_for_deep_stack() public {
    mgv.setMaxRecursionDepth(100);
    gaslimit = 200_000_000;
    // Same as testFail_take_more_than_first_fails_for_deep_stack, but verifies that the clog persists after a successful order.
    takeSome(minVolume);
    vm.expectRevert();
    vm.prank($(taker));
    mgv.marketOrderByTickCustom(olKey, Tick.wrap(MAX_TICK), minVolume + 1, false, type(uint).max);
  }
}

contract TooMuchGasClogTest is TooDeepRecursionClogTest {
  function setUp() public override {
    gasreq = 2_000_000;
    super.setUp();
    mgv.setMaxGasreqForFailingOffers(5_000_000);
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

contract MaxRecursionDepthFuzzTest is MangroveTest, IMaker {
  mapping(uint => bool) internal shouldFailOffer;

  TestTaker internal taker;
  uint internal volume = 1 ether;
  uint internal gasreq = 100_000;
  uint internal gaslimit = 200_000_000;
  uint internal expectedGot;

  function makerExecute(MgvLib.SingleOrder calldata sor) public virtual override returns (bytes32 result) {
    result = bytes32(0);
    bool shouldFail = shouldFailOffer[sor.offerId];

    if (shouldFail) {
      revert("AH AH AH!");
    }
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) external override {}

  function setUp() public virtual override {
    super.setUp();

    // Some taker
    taker = setupTaker(olKey, "Taker");
    deal($(quote), address(taker), 100000 ether);
    taker.approveMgv(quote, 100000 ether);

    deal($(base), $(this), 100000 ether);
  }

  function createOffers(uint count, uint failureMode, uint seed, uint depth) internal {
    for (uint i; i < count; ++i) {
      bool fail;
      if (failureMode == 0) {
        fail = false;
      } else if (failureMode == 1) {
        fail = true;
      } else if (failureMode == 2) {
        fail = uint(keccak256(abi.encodePacked(seed, i))) % 2 == 0;
      }
      uint offerId = mgv.newOfferByTick(olKey, Tick.wrap(0), volume, gasreq, 0);
      if (!fail && depth > i) {
        expectedGot += volume;
      }
      shouldFailOffer[offerId] = fail;
    }
  }

  function takeSome(uint wants) public {
    (uint takerGot,) = taker.marketOrder{gas: gaslimit}(0, wants, false);
    assertEq(takerGot, expectedGot, "Taker should get volumes from successes");
  }

  function take_recursion_depth_with_parameterized_offers(uint8 depth, uint8 seed, uint failureMode, uint failDepth)
    internal
  {
    vm.assume(depth > 0);
    createOffers(200, failureMode, seed, depth);
    mgv.setMaxRecursionDepth(depth);

    vm.prank($(taker));
    try mgv.marketOrderByTickCustom(olKey, Tick.wrap(MAX_TICK), 200 ether, false, type(uint).max) {
      assertLe(depth, failDepth, "should only succeed at lower depths");
    } catch {
      assertGt(depth, failDepth, "should only fail for high depth");
    }
  }

  function test_take_recursion_depth_succeeding_offers(uint8 depth) public {
    take_recursion_depth_with_parameterized_offers(depth, 0, 0, 79); // 80 with optimization and 200 runs
  }

  function test_take_recursion_depth_failing_offers(uint8 depth) public {
    take_recursion_depth_with_parameterized_offers(depth, 0, 1, 79); // 80 with optimization and 200 runs
  }

  function test_take_recursion_depth_random_failing_offers(uint8 depth, uint8 seed) public {
    take_recursion_depth_with_parameterized_offers(depth, seed, 2, 79); // 80 with optimization and 200 runs
  }
}
