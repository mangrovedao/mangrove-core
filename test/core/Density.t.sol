// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

// import "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";

// In these tests, the testing contract is the market maker.
contract DensityTest is Test2 {
  uint d;

  function test_density_manual() public {
    // test that going to floating point & back works
    d = 1 << 32;
    assertD(1 << 32, "1");
    d = 0;
    assertD(0, "0");
    d = 1;
    assertD(1, "1 * 2^-32");
    d = 2;
    assertD(2, "2 * 2^-32");
    d = 3;
    assertD(3, "3 * 2^-32");
    d = 4;
    assertD(4, "4 * 2^-32");
    d = 5;
    assertD(5, "5 * 2^-32");
    d = 6;
    assertD(6, "6 * 2^-32");
    d = 7;
    assertD(7, "7 * 2^-32");
    d = 8;
    assertD(8, "8 * 2^-32");
    d = 9;
    assertD(8, "9 * 2^-32");
    d = 10;
    assertD(10, "10 * 2^-32");
    d = 11;
    assertD(10, "11 * 2^-32");
    d = type(uint).max;
    assertD(7 << 253, "2^256-1");
  }

  function assertD(uint expectedFixp, string memory err) internal {
    uint fixp = DensityLib.fromFixed(d).toFixed();
    assertEq(fixp, expectedFixp, string.concat(err, ": fixed -> floating -> fixed"));
    if (expectedFixp != 0 && expectedFixp < type(uint).max / 100) {
      // check approx/original ratio

      assertLe(fixp, d, string.concat(err, ": ratio"));
      assertGe(fixp * 100 / d, 80, string.concat(err, ": ratio"));
    }
  }

  function test_density_convert_auto(uint128 fixp) public {
    vm.assume(fixp != 0);
    Density density = DensityLib.fromFixed(fixp);
    assertLe(density.mantissa(), 4, "mantissa too large");
    assertLe(density.exponent(), 127, "exponent too large");
    assertLe(density.toFixed(), fixp, "error too large (above)");
    // maximum error is 20%,
    // for instance the fixp 1001....1, which gets approximated to 100....0
    //                   or  01001...1, which gets approximated to 0100...0
    assertGe(density.toFixed() * 100 / fixp, 80, "error too large (below)");
  }

  function test_multiply_manual() public {
    assertMultiply({mantissa: 0, exp: 0, mult: 0, expected: 0});
    assertMultiply({mantissa: 0, exp: 0, mult: 1, expected: 0});
    assertMultiply({mantissa: 1, exp: 0, mult: 1, expected: 0});
    assertMultiply({mantissa: 2, exp: 0, mult: 2, expected: 0});
    assertMultiply({mantissa: 3, exp: 0, mult: 2 ** 32, expected: 3});
    assertMultiply({mantissa: 0, exp: 32, mult: 1, expected: 1});
    assertMultiply({mantissa: 0, exp: 32, mult: 1, expected: 1});
    assertMultiply({mantissa: 2, exp: 33, mult: 2, expected: 6});
  }

  function assertMultiply(uint mantissa, uint exp, uint mult, uint expected) internal {
    Density density = DensityLib.make(mantissa, exp);
    assertEq(
      density.multiply(mult),
      expected,
      string.concat(
        "float: ",
        toString(density),
        ", mult:",
        vm.toString(mult),
        " (mantissa: ",
        vm.toString(mantissa),
        ", exp:",
        vm.toString(exp),
        ")"
      )
    );
  }

  function test_density_multiply_auto(uint8 _mantissa, uint8 _exp, uint96 _m) public {
    uint mantissa = bound(_mantissa, 0, 3);
    uint exp = bound(_exp, 0, 127);
    uint m = uint(_m);
    Density density = DensityLib.make(mantissa, exp);
    uint res = density.multiply(m);
    if (exp < 2) {
      uint num = m * mantissa;
      assertEq(res, num / (2 ** 32), "wrong multiply, small exp");
    } else {
      uint converted = (mantissa | 4) << (exp - 2);
      uint num = m * converted;
      assertEq(res, num / (2 ** 32), "wrong multiply, big exp");
    }
  }

  function test_fixedFromParams() public {
    uint res = DensityLib.fixedFromParams({
      outbound_decimals: 6,
      gasprice_in_gwei: 250,
      eth_in_usdx100: 1 * 100,
      outbound_display_in_usdx100: 1000 * 100,
      cover_factor: 1000
    });
    assertEq(toString(DensityLib.fromFixed(res)), "1 * 2^-2");
    res = DensityLib.fixedFromParams({
      outbound_decimals: 18,
      gasprice_in_gwei: 2500,
      eth_in_usdx100: 10000 * 100,
      outbound_display_in_usdx100: 1 * 100,
      cover_factor: 1000
    });
    assertEq(toString(DensityLib.fromFixed(res)), "1.25 * 2^64");
  }
}
