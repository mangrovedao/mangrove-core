// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

// import "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Test2.sol";
// import "abdk-libraries-solidity/ABDKMathQuad.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/LogPriceConversionLib.sol";

// In these tests, the testing contract is the market maker.
contract ConstantsTest is Test2 {
  function test_constants_min_max_price() public {
    (uint man, uint exp) = LogPriceConversionLib.priceFromLogPrice(MIN_LOG_PRICE);
    assertEq(man, MIN_PRICE_MANTISSA);
    assertEq(int(exp), MIN_PRICE_EXP);
    (man, exp) = LogPriceConversionLib.priceFromLogPrice(MAX_LOG_PRICE);
    assertEq(man, MAX_PRICE_MANTISSA);
    assertEq(int(exp), MAX_PRICE_EXP);
  }

  // Since "Only direct number constants and references to such constants are supported by inline assembly", NOT_TOPBIT is not defined in terms of TOPBIT. Here we check that its definition is correct.
  function test_not_topbit_is_negation_of_topbit() public {
    assertEq(TOPBIT, ~NOT_TOPBIT, "TOPBIT != ~NOT_TOPBIT");
  }

  // Some BitLib.ctz64 relies on specific level sizes
  function test_level_sizes() public {
    assertLe(LEVEL3_SIZE, int(MAX_LEVEL_SIZE), "bad level3 size");
    assertGt(LEVEL3_SIZE, 0);
    assertLe(LEVEL2_SIZE, int(MAX_LEVEL_SIZE), "bad level2 size");
    assertGt(LEVEL2_SIZE, 0);
    assertLe(LEVEL1_SIZE, int(MAX_LEVEL_SIZE), "bad level1 size");
    assertGt(LEVEL1_SIZE, 0);
    assertLe(LEVEL0_SIZE, int(MAX_LEVEL_SIZE), "bad level0 size");
    assertGt(LEVEL0_SIZE, 0);
  }

  // checks that there is no overflow
  function test_maxSafeVolumeIsSafeLowLevel() public {
    assertGt(MAX_SAFE_VOLUME * ((1 << MANTISSA_BITS) - 1), 0);
  }
}
