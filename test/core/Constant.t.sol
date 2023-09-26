// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";

// In these tests, the testing contract is the market maker.
contract ConstantsTest is MangroveTest {
  function test_constants_min_max_ratio() public {
    (uint man, uint exp) = TickLib.ratioFromTick(Tick.wrap(MIN_TICK));
    assertEq(man, MIN_RATIO_MANTISSA);
    assertEq(int(exp), MIN_RATIO_EXP);
    (man, exp) = TickLib.ratioFromTick(Tick.wrap(MAX_TICK));
    assertEq(man, MAX_RATIO_MANTISSA);
    assertEq(int(exp), MAX_RATIO_EXP);
  }

  function test_constants_min_max_ratio2() public {
    Tick tick;
    tick = TickLib.tickFromNormalizedRatio(MIN_RATIO_MANTISSA, uint(MIN_RATIO_EXP));
    assertEq(tick, Tick.wrap(MIN_TICK));
    tick = TickLib.tickFromNormalizedRatio(MAX_RATIO_MANTISSA, uint(MAX_RATIO_EXP));
    assertEq(tick, Tick.wrap(MAX_TICK));
  }

  function test_max_safe_gives() public {
    // check no revert
    TickLib.inboundFromOutboundUp(Tick.wrap(MAX_TICK), MAX_SAFE_GIVES);
    vm.expectRevert("mgv/mulDivPow2/overflow");
    TickLib.inboundFromOutbound(Tick.wrap(MAX_TICK), MAX_SAFE_GIVES + 1);
  }

  // Since "Only direct number constants and references to such constants are supported by inline assembly", NOT_TOPBIT is not defined in terms of TOPBIT. Here we check that its definition is correct.
  function test_not_topbit_is_negation_of_topbit() public {
    assertEq(TOPBIT, ~NOT_TOPBIT, "TOPBIT != ~NOT_TOPBIT");
  }

  // Some BitLib.ctz64 relies on specific level sizes
  function test_level_sizes() public {
    assertLe(ROOT_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(ROOT_SIZE, 0, "root size too small");
    assertLe(LEVEL_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(LEVEL_SIZE, 0, "level size too small");
  }

  // make sure TICK_BITS in Constants.sol matches the tick bits used in offer struct
  function test_tick_bits() public {
    assertEq(TICK_BITS, OfferLib.tick_bits);
  }

  // make sure OFFER_BITS in Constants.sol matches the id fields used in structs
  function test_offer_bits() public {
    assertEq(OFFER_BITS, LocalLib.last_bits);
  }

  // Since constant expressions are (as of solidity 0.8.21) not evaluated at compile time, we write all constants in Constants.sol as literals and test their values here:
  function test_constant_expressions() public {
    assertEq(MAX_BIN, -MIN_BIN - 1, "MAX_BIN");
    assertEq(LEAF_SIZE, int(2 ** LEAF_SIZE_BITS), "LEAF_SIZE");
    assertEq(LEVEL_SIZE, int(2 ** LEVEL_SIZE_BITS), "LEVEL_SIZE");
    assertEq(ROOT_SIZE, int(2 ** ROOT_SIZE_BITS), "ROOT_SIZE");
    assertEq(LEAF_SIZE_MASK, ~(ONES << LEAF_SIZE_BITS), "LEAF_SIZE_MASK");
    assertEq(LEVEL_SIZE_MASK, ~(ONES << LEVEL_SIZE_BITS), "LEVEL_SIZE_MASK");
    assertEq(ROOT_SIZE_MASK, ~(ONES << ROOT_SIZE_BITS), "ROOT_SIZE_MASK");
    assertEq(NUM_LEVEL1, int(ROOT_SIZE), "NUM_lEVEL1");
    assertEq(NUM_LEVEL2, NUM_LEVEL1 * LEVEL_SIZE, "NUM_LEVEL2");
    assertEq(NUM_LEVEL3, NUM_LEVEL2 * LEVEL_SIZE, "NUM_LEVEL3");
    assertEq(NUM_LEAFS, NUM_LEVEL3 * LEVEL_SIZE, "NUM_LEAFS");
    assertEq(NUM_BINS, NUM_LEAFS * LEAF_SIZE, "NUM_BINS");
    assertEq(OFFER_MASK, ONES >> (256 - OFFER_BITS), "OFFER_MASK");
    assertEq(MIN_TICK, -((1 << 20) - 1), "MIN_TICK");
    assertEq(MAX_TICK, -MIN_TICK, "MAX_TICK");
    assertEq(MANTISSA_BITS_MINUS_ONE, MANTISSA_BITS - 1, "MANTISSA_BITS_MINUS_ONE");
    assertEq(MAX_SAFE_GIVES, type(uint).max / MAX_RATIO_MANTISSA, "MAX_SAFE_GIVES");
    assertEq(MIN_BIN_ALLOWED, MIN_TICK, "MIN_BIN_ALLOWED");
    assertEq(MAX_BIN_ALLOWED, MAX_TICK, "MAX_BIN_ALLOWED");
    assertEq(MAX_SAFE_VOLUME, (1 << MAX_SAFE_VOLUME_BITS) - 1);
  }

  // For the ratio computed in TickLib.tickFromVolumes to be valid, it must represent a number less than the maximum ratio. Since it is computed by (inbound << MAX_SAFE_VOLUME_BITS) / outbound and inbound <= MAX_SAFE_VOLUME,
  function test_tickFromVolumes_is_maxRatio_safe() public {
    assertTrue(MAX_SAFE_VOLUME <= MAX_RATIO_MANTISSA, "MAX_SAFE_VOLUME is too big");
    // The check above only holds because it can ignore MAX_RATIO_EXP;
    assertTrue(MAX_RATIO_EXP == 0, "max ratio exp must be 0 for the check above to hold");
  }

  // In TickLib.tickFromVolumes, the (uint) exp of a normalized float is computed by MAX_SAFE_VOLUME_BITS - log2(number) + MANTISSA_BITS_MINUS_ONE
  // Lack of underflow is only guaranteed if the maximum possible log2 does not yield a < 0 exp.
  function test_tickFromVolumes_underflow_safe() public {
    assertTrue(255 - MANTISSA_BITS_MINUS_ONE < MAX_SAFE_VOLUME_BITS, "risk of underflow in TickLib.tickFromVolumes");
  }
}
