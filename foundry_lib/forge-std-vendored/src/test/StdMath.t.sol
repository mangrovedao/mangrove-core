// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

import "../Test.sol";

contract StdMathTest is Test {
  function testGetAbs() external {
    assertEq(stdMath.abs(-50), 50);
    assertEq(stdMath.abs(50), 50);
    assertEq(stdMath.abs(-1337), 1337);
    assertEq(stdMath.abs(0), 0);

    assertEq(stdMath.abs(type(int).min), (type(uint).max >> 1) + 1);
    assertEq(stdMath.abs(type(int).max), (type(uint).max >> 1));
  }

  function testGetAbs_Fuzz(int a) external {
    uint manualAbs = getAbs(a);

    uint abs = stdMath.abs(a);

    assertEq(abs, manualAbs);
  }

  function testGetDelta_Uint() external {
    assertEq(stdMath.delta(uint(0), uint(0)), 0);
    assertEq(stdMath.delta(uint(0), uint(1337)), 1337);
    assertEq(stdMath.delta(uint(0), type(uint64).max), type(uint64).max);
    assertEq(stdMath.delta(uint(0), type(uint128).max), type(uint128).max);
    assertEq(stdMath.delta(uint(0), type(uint).max), type(uint).max);

    assertEq(stdMath.delta(0, uint(0)), 0);
    assertEq(stdMath.delta(1337, uint(0)), 1337);
    assertEq(stdMath.delta(type(uint64).max, uint(0)), type(uint64).max);
    assertEq(stdMath.delta(type(uint128).max, uint(0)), type(uint128).max);
    assertEq(stdMath.delta(type(uint).max, uint(0)), type(uint).max);

    assertEq(stdMath.delta(1337, uint(1337)), 0);
    assertEq(stdMath.delta(type(uint).max, type(uint).max), 0);
    assertEq(stdMath.delta(5000, uint(1250)), 3750);
  }

  function testGetDelta_Uint_Fuzz(uint a, uint b) external {
    uint manualDelta;
    if (a > b) {
      manualDelta = a - b;
    } else {
      manualDelta = b - a;
    }

    uint delta = stdMath.delta(a, b);

    assertEq(delta, manualDelta);
  }

  function testGetDelta_Int() external {
    assertEq(stdMath.delta(int(0), int(0)), 0);
    assertEq(stdMath.delta(int(0), int(1337)), 1337);
    assertEq(stdMath.delta(int(0), type(int64).max), type(uint64).max >> 1);
    assertEq(stdMath.delta(int(0), type(int128).max), type(uint128).max >> 1);
    assertEq(stdMath.delta(int(0), type(int).max), type(uint).max >> 1);

    assertEq(stdMath.delta(0, int(0)), 0);
    assertEq(stdMath.delta(1337, int(0)), 1337);
    assertEq(stdMath.delta(type(int64).max, int(0)), type(uint64).max >> 1);
    assertEq(stdMath.delta(type(int128).max, int(0)), type(uint128).max >> 1);
    assertEq(stdMath.delta(type(int).max, int(0)), type(uint).max >> 1);

    assertEq(stdMath.delta(-0, int(0)), 0);
    assertEq(stdMath.delta(-1337, int(0)), 1337);
    assertEq(
      stdMath.delta(type(int64).min, int(0)),
      (type(uint64).max >> 1) + 1
    );
    assertEq(
      stdMath.delta(type(int128).min, int(0)),
      (type(uint128).max >> 1) + 1
    );
    assertEq(stdMath.delta(type(int).min, int(0)), (type(uint).max >> 1) + 1);

    assertEq(stdMath.delta(int(0), -0), 0);
    assertEq(stdMath.delta(int(0), -1337), 1337);
    assertEq(
      stdMath.delta(int(0), type(int64).min),
      (type(uint64).max >> 1) + 1
    );
    assertEq(
      stdMath.delta(int(0), type(int128).min),
      (type(uint128).max >> 1) + 1
    );
    assertEq(stdMath.delta(int(0), type(int).min), (type(uint).max >> 1) + 1);

    assertEq(stdMath.delta(1337, int(1337)), 0);
    assertEq(stdMath.delta(type(int).max, type(int).max), 0);
    assertEq(stdMath.delta(type(int).min, type(int).min), 0);
    assertEq(stdMath.delta(type(int).min, type(int).max), type(uint).max);
    assertEq(stdMath.delta(5000, int(1250)), 3750);
  }

  function testGetDelta_Int_Fuzz(int a, int b) external {
    uint absA = getAbs(a);
    uint absB = getAbs(b);
    uint absDelta = absA > absB ? absA - absB : absB - absA;

    uint manualDelta;
    if ((a >= 0 && b >= 0) || (a < 0 && b < 0)) {
      manualDelta = absDelta;
    }
    // (a < 0 && b >= 0) || (a >= 0 && b < 0)
    else {
      manualDelta = absA + absB;
    }

    uint delta = stdMath.delta(a, b);

    assertEq(delta, manualDelta);
  }

  function testGetPercentDelta_Uint() external {
    assertEq(stdMath.percentDelta(uint(0), uint(1337)), 1e18);
    assertEq(stdMath.percentDelta(uint(0), type(uint64).max), 1e18);
    assertEq(stdMath.percentDelta(uint(0), type(uint128).max), 1e18);
    assertEq(stdMath.percentDelta(uint(0), type(uint192).max), 1e18);

    assertEq(stdMath.percentDelta(1337, uint(1337)), 0);
    assertEq(stdMath.percentDelta(type(uint192).max, type(uint192).max), 0);
    assertEq(stdMath.percentDelta(0, uint(2500)), 1e18);
    assertEq(stdMath.percentDelta(2500, uint(2500)), 0);
    assertEq(stdMath.percentDelta(5000, uint(2500)), 1e18);
    assertEq(stdMath.percentDelta(7500, uint(2500)), 2e18);

    vm.expectRevert(stdError.divisionError);
    stdMath.percentDelta(uint(1), 0);
  }

  function testGetPercentDelta_Uint_Fuzz(uint192 a, uint192 b) external {
    vm.assume(b != 0);
    uint manualDelta;
    if (a > b) {
      manualDelta = a - b;
    } else {
      manualDelta = b - a;
    }

    uint manualPercentDelta = (manualDelta * 1e18) / b;
    uint percentDelta = stdMath.percentDelta(a, b);

    assertEq(percentDelta, manualPercentDelta);
  }

  function testGetPercentDelta_Int() external {
    assertEq(stdMath.percentDelta(int(0), int(1337)), 1e18);
    assertEq(stdMath.percentDelta(int(0), -1337), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int64).min), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int128).min), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int192).min), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int64).max), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int128).max), 1e18);
    assertEq(stdMath.percentDelta(int(0), type(int192).max), 1e18);

    assertEq(stdMath.percentDelta(1337, int(1337)), 0);
    assertEq(stdMath.percentDelta(type(int192).max, type(int192).max), 0);
    assertEq(stdMath.percentDelta(type(int192).min, type(int192).min), 0);

    assertEq(stdMath.percentDelta(type(int192).min, type(int192).max), 2e18); // rounds the 1 wei diff down
    assertEq(
      stdMath.percentDelta(type(int192).max, type(int192).min),
      2e18 - 1
    ); // rounds the 1 wei diff down
    assertEq(stdMath.percentDelta(0, int(2500)), 1e18);
    assertEq(stdMath.percentDelta(2500, int(2500)), 0);
    assertEq(stdMath.percentDelta(5000, int(2500)), 1e18);
    assertEq(stdMath.percentDelta(7500, int(2500)), 2e18);

    vm.expectRevert(stdError.divisionError);
    stdMath.percentDelta(int(1), 0);
  }

  function testGetPercentDelta_Int_Fuzz(int192 a, int192 b) external {
    vm.assume(b != 0);
    uint absA = getAbs(a);
    uint absB = getAbs(b);
    uint absDelta = absA > absB ? absA - absB : absB - absA;

    uint manualDelta;
    if ((a >= 0 && b >= 0) || (a < 0 && b < 0)) {
      manualDelta = absDelta;
    }
    // (a < 0 && b >= 0) || (a >= 0 && b < 0)
    else {
      manualDelta = absA + absB;
    }

    uint manualPercentDelta = (manualDelta * 1e18) / absB;
    uint percentDelta = stdMath.percentDelta(a, b);

    assertEq(percentDelta, manualPercentDelta);
  }

  /*//////////////////////////////////////////////////////////////////////////
                                   HELPERS
    //////////////////////////////////////////////////////////////////////////*/

  function getAbs(int a) private pure returns (uint) {
    if (a < 0) return a == type(int).min ? uint(type(int).max) + 1 : uint(-a);

    return uint(a);
  }
}
