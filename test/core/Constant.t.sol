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
    assertEq(TICK_BITS, OfferLib.tick_bits);
  }

  // make sure OFFER_BITS in Constants.sol matches the id fields used in structs
  function test_offer_bits() public {
    assertEq(OFFER_BITS, LocalLib.last_bits);
  }
}
