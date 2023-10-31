// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";

contract Script2Test is Test2 {
  function aeq(uint amt, uint unit, uint dp, string memory expected) internal {
    assertEq(toFixed(amt, unit, dp), expected);
    // console.log("%s | %s", (amt, unit, dp), expected);
  }

  function aeq(uint amt, uint unit, string memory expected) internal {
    assertEq(toFixed(amt, unit), expected);
    // console.log("%s | %s", toFixed(amt, unit), expected);
  }

  function test_basic() public {
    aeq(10 ** 18, 18, "1");
    aeq(2 * 10 ** 6, 6, "2");
    aeq(0, 18, "0");
    aeq(0, 0, "0");
    aeq(23, 0, "23");
    aeq(1, 1, "0.1");
    aeq(1, 2, "0.01");
    aeq(55, 4, "0.0055");
    aeq(6.35 * 10 ** 5 + 1, 5, "6.35001");
    aeq(6035, 3, "6.035");
    aeq(1000, 2, "10");
  }

  function test_dp() public {
    aeq(1, 0, 0, "1");
    aeq(1, 1, 0, unicode"0.…");
    aeq(1, 1, 1, "0.1");
    aeq(12, 2, 1, unicode"0.1…");
    aeq(12, 3, 1, unicode"0.0…");
    aeq(12, 3, 2, unicode"0.01…");
    aeq(12, 3, 3, "0.012");
    aeq(1, 0, 0, "1");
  }
}
