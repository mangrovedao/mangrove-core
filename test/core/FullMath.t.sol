// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_test/lib/MangroveTest.sol";
// import {Fullmath as F} from "mgv_lib/FullMath.sol";

// Only mulDivPow2 needs testing
contract FullMathTest is Test2 {
  FullMathProxy fmp;

  function setUp() public virtual {
    fmp = new FullMathProxy();
  }

  function test_fuzz_ceil(uint a, uint b, uint e) public {
    e = bound(e, 0, 255);
    assertMulUp(a, b, e, "fuzz_ceil");
  }

  function test_fuzz_floor(uint a, uint b, uint e) public {
    e = bound(e, 0, 255);
    assertMul(a, b, e, "fuzz_ceil");
  }

  function test_manual1() public {
    for (uint e = 0; e < 256; e++) {
      assertMul(type(uint).max, type(uint).max, e, "floor");
      assertMulUp(type(uint).max, type(uint).max, e, "ceil");
    }
  }

  function test_manual_up() public {
    for (uint e = 0; e < 256; e++) {
      assertMulUp(1, (1 << e) + 1, e, "up1");
      assertMulUp(1, (1 << e) - 1, e, "up2");
      assertMulUp(1 << (256 - e) + 1, (1 << e) + 1, e, "up3");
      assertMulUp(1 << (256 - e) + 1, (1 << e) - 1, e, "up4");
    }
  }

  /* ************
    Utility
  ************* */

  function assertMul(uint a, uint b, uint e, bool roundUp, string memory err) internal {
    require(e <= 255, "e>255 not valid for FullMath.mulDiv[roundingUp]");

    uint expected;
    bool expected_success = false;
    if (roundUp) {
      try fmp.mulDivRoundingUp(a, b, 1 << e) returns (uint got) {
        expected = got;
        expected_success = true;
      } catch {}
    } else {
      try fmp.mulDiv(a, b, 1 << e) returns (uint got) {
        expected = got;
        expected_success = true;
      } catch {}
    }

    uint actual;
    bool actual_success = false;
    try fmp.mulDivPow2(a, b, e, roundUp) returns (uint got) {
      actual = got;
      actual_success = true;
    } catch {}

    if (expected != actual || expected_success != actual_success) {
      emit log(string.concat("Error: mulDiv != mulDivPow2(", roundUp ? "ceil" : "floor", ")"));
      emit log(err);
      emit log_named_string("         a", vm.toString(a));
      emit log_named_string("         b", vm.toString(b));
      emit log_named_string("      expn", vm.toString(e));
      if (expected_success != actual_success) {
        emit log_named_string("    mulDiv", vm.toString(expected_success));
        emit log_named_string("mulDivPow2", vm.toString(actual_success));
      } else {
        emit log_named_string("    mulDiv", vm.toString(expected));
        emit log_named_string("mulDivPow2", vm.toString(actual));
      }
    }
  }

  function assertMul(uint a, uint b, uint e, string memory err) internal {
    assertMul(a, b, e, false, err);
  }

  function assertMulUp(uint a, uint b, uint e, string memory err) internal {
    assertMul(a, b, e, true, err);
  }
}

contract FullMathProxy {
  function mulDivRoundingUp(uint a, uint b, uint e) external pure returns (uint) {
    return FullMath.mulDivRoundingUp(a, b, e);
  }

  function mulDiv(uint a, uint b, uint e) external pure returns (uint) {
    return FullMath.mulDiv(a, b, e);
  }

  function mulDivPow2(uint a, uint b, uint e, bool roundUp) external pure returns (uint) {
    return FullMath.mulDivPow2(a, b, e, roundUp);
  }
}
