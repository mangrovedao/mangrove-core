// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/TickConversionLib.sol";
import {tick_bits} from "mgv_src/preprocessed/MgvOffer.post.sol";
import {last_bits} from "mgv_src/preprocessed/MgvLocal.post.sol";

// In these tests, the testing contract is the market maker.
contract ConstantsTest is MangroveTest {
  function test_constants_min_max_ratio() public {
    (uint man, uint exp) = TickConversionLib.ratioFromTick(Tick.wrap(MIN_TICK));
    assertEq(man, MIN_RATIO_MANTISSA);
    assertEq(int(exp), MIN_RATIO_EXP);
    (man, exp) = TickConversionLib.ratioFromTick(Tick.wrap(MAX_TICK));
    assertEq(man, MAX_RATIO_MANTISSA);
    assertEq(int(exp), MAX_RATIO_EXP);
  }

  function test_constants_min_max_ratio2() public {
    Tick tick;
    tick = TickConversionLib.tickFromNormalizedRatio(MIN_RATIO_MANTISSA, uint(MIN_RATIO_EXP));
    assertEq(tick, Tick.wrap(MIN_TICK));
    tick = TickConversionLib.tickFromNormalizedRatio(MAX_RATIO_MANTISSA, uint(MAX_RATIO_EXP));
    assertEq(tick, Tick.wrap(MAX_TICK));
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

  // checks that there is no overflow
  function test_maxSafeVolumeIsSafeLowLevel() public {
    assertGt(MAX_SAFE_VOLUME * ((1 << MANTISSA_BITS) - 1), 0);
  }

  // make sure TICK_BITS in Constants.sol matches the tick bits used in offer struct
  function test_tick_bits() public {
    assertEq(TICK_BITS, tick_bits);
  }

  // make sure OFFER_BITS in Constants.sol matches the id fields used in structs
  function test_offer_bits() public {
    assertEq(OFFER_BITS, last_bits);
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
    assertEq(MAX_SAFE_VOLUME, (1 << (256 - MANTISSA_BITS)) - 1, "MAX_SAFE_VOLUME");
    assertEq(MIN_BIN_ALLOWED, MIN_TICK, "MIN_BIN_ALLOWED");
    assertEq(MAX_BIN_ALLOWED, MAX_TICK, "MAX_BIN_ALLOWED");
  }
}
