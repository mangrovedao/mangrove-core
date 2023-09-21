// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/TickConversionLib.sol";

// In these tests, the testing contract is the market maker.
contract ConstantsTest is Test2 {
  function test_constants_min_max_ratio() public {
    (uint man, uint exp) = TickConversionLib.ratioFromTick(MIN_TICK);
    assertEq(man, MIN_RATIO_MANTISSA);
    assertEq(int(exp), MIN_RATIO_EXP);
    (man, exp) = TickConversionLib.ratioFromTick(MAX_TICK);
    assertEq(man, MAX_RATIO_MANTISSA);
    assertEq(int(exp), MAX_RATIO_EXP);
  }

  // Since "Only direct number constants and references to such constants are supported by inline assembly", NOT_TOPBIT is not defined in terms of TOPBIT. Here we check that its definition is correct.
  function test_not_topbit_is_negation_of_topbit() public {
    assertEq(TOPBIT, ~NOT_TOPBIT, "TOPBIT != ~NOT_TOPBIT");
  }

  // Some BitLib.ctz64 relies on specific level sizes
  function test_level_sizes() public {
    assertLe(ROOT_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(ROOT_SIZE, 0, "level3 size too small");
    assertLe(LEVEL_SIZE, int(MAX_FIELD_SIZE), "level size too big");
    assertGt(LEVEL_SIZE, 0, "level size too small");
  }

  // checks that there is no overflow
  function test_maxSafeVolumeIsSafeLowLevel() public {
    assertGt(MAX_SAFE_VOLUME * ((1 << MANTISSA_BITS) - 1), 0);
  }
}
