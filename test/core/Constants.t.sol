// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";

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

  // Some BitLib.ctz64 relies on specific level sizes
  function test_level_sizes() public {
    assertLe(ROOT_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(ROOT_SIZE, 0, "root size too small");
    assertLe(LEVEL_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(LEVEL_SIZE, 0, "level size too small");
  }

  // checks that there is no overflow, assert is useless but should prevent optimizing away
  function test_max_safe_volume_is_safe_low_level() public {
    assertGt(MAX_SAFE_VOLUME * ((1 << MANTISSA_BITS) - 1), 0);
  }

  // make sure TICK_BITS in Constants.sol matches the tick bits used in offer struct
  function test_tick_bits() public {
    assertEq(TICK_BITS, OfferLib.tick_bits);
  }

  // make sure OFFER_BITS in Constants.sol matches the id fields used in structs
  function test_offer_bits() public {
    assertEq(OFFER_BITS, LocalLib.last_bits);
  }

  // in `TickLib.ratioFromTick`, for maximum precision log_{1.0001}(2) is given shifted 235 bits left, and the tick is shifted by the same amount. This is only possible if the tick is on 21 bits or less.
  function test_log_bp_shift() public {
    assertLe(BitLib.fls(uint(MAX_TICK)), 256 - LOG_BP_SHIFT, "MAX_TICK");
    assertLe(BitLib.fls(uint(-MIN_TICK)), 256 - LOG_BP_SHIFT, "MIN_TICK");
  }

  function test_offer_limit_is_volume_limit() public {
    assertEq((1 << OfferLib.gives_bits) - 1, MAX_SAFE_VOLUME);
  }

  // Since constant expressions are (as of solidity 0.8.21) not evaluated at compile time, we write all constants in Constants.sol as literals and test their values here:
  function test_constant_expressions() public {
    assertEq(TOPBIT, 1 << 255, "TOPBIT");
    assertEq(NOT_TOPBIT, ~TOPBIT, "TOPBIT != ~NOT_TOPBIT");
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
    assertEq(MANTISSA_BITS_MINUS_ONE, MANTISSA_BITS - 1, "MANTISSA_BITS_MINUS_ONE");
    assertEq(MAX_SAFE_VOLUME, (1 << (256 - MANTISSA_BITS - 1)) - 1, "MAX_SAFE_VOLUME");
    assertEq(MIN_BIN, -NUM_BINS / 2, "MIN_BIN");
    assertEq(MAX_BIN, NUM_BINS / 2 - 1, "MAX_BIN");

    assertEq(DensityLib.BITS, LocalLib.density_bits, "Density bits");
  }
}
