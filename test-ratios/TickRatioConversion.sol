// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";
import "mgv_lib/TickLib.sol";

// Will check that ratios are within 1/RELATIVE_ERROR_THRESHOLD of reference ratios
uint constant RELATIVE_ERROR_THRESHOLD = 1e15;

// Actual test contracts are at the end of this file
abstract contract TickRatioConversionTest is Test2 {
  string ratios_file;

  constructor(uint num) {
    ratios_file = string.concat(vm.projectRoot(), "/test-ratios/ref_ratios_", vm.toString(num), "_of_10.jsonl");
  }

  // fields must be in alphabetical order here
  struct Ratio {
    uint exp;
    string sig;
    int tick;
  }

  function test_ratioFromTick() public {
    string memory line;
    Ratio memory ref;
    uint ref_sig;

    // Gas / memory management
    vm.pauseGasMetering();
    bytes32 free_mem;
    assembly ("memory-safe") {
      free_mem := mload(0x40)
    }

    // Counter to check that no tick is missing
    int tick_counter = type(int).min;

    // Read each line of ratios_file, extract tick and ratio, compare to ref
    while (bytes(line = vm.readLine(ratios_file)).length != 0) {
      // Read & parse
      ref = abi.decode(vm.parseJson(line), (Ratio));
      ref_sig = vm.parseUint(ref.sig);

      // Initialize tick counter
      if (tick_counter == type(int).min) {
        tick_counter = ref.tick;
      }
      // Check no tick missing
      require(tick_counter++ == ref.tick, string.concat("Missing tick ", vm.toString(ref.tick)));

      (uint cur_sig, uint cur_exp) = TickLib.ratioFromTick(Tick.wrap(ref.tick));

      // Check normalization
      assertEq(BitLib.fls(cur_sig), MANTISSA_BITS_MINUS_ONE, string.concat("Wrong fls ", vm.toString(ref.tick)));

      // Compare to reference
      // compute abs error relative to reference
      (uint big, uint small) = cur_sig > ref_sig ? (cur_sig, ref_sig) : (ref_sig, cur_sig);
      uint absRelErr = (big - small) * RELATIVE_ERROR_THRESHOLD / ref_sig;

      if (absRelErr > 0) {
        console.log("Error at tick", ref.tick);
        console.log("    absRelErr", absRelErr);
        console.log("      ref sig", ref_sig);
        console.log("      ref exp", ref.exp);
        console.log("          vs.");
        console.log("      cur sig", cur_sig);
        console.log("      cur exp", cur_exp);
        fail();
      }

      // Check that tickFromRatio(ratioFromTick(tick)) == tick
      Tick new_tick = TickLib.tickFromRatio(cur_sig, int(cur_exp));
      assertEq(Tick.unwrap(new_tick), ref.tick, "tickFromRatio not right inverse of ratioFromTick");

      // Memory management
      assembly ("memory-safe") {
        mstore(0x40, free_mem)
      }
    }
  }
}

// number of contracts must match number of ref_ratios_* files
contract TickRatioConversionTest1 is TickRatioConversionTest(1) {}

contract TickRatioConversionTest2 is TickRatioConversionTest(2) {}

contract TickRatioConversionTest3 is TickRatioConversionTest(3) {}

contract TickRatioConversionTest4 is TickRatioConversionTest(4) {}

contract TickRatioConversionTest5 is TickRatioConversionTest(5) {}

contract TickRatioConversionTest6 is TickRatioConversionTest(6) {}

contract TickRatioConversionTest7 is TickRatioConversionTest(7) {}

contract TickRatioConversionTest8 is TickRatioConversionTest(8) {}

contract TickRatioConversionTest9 is TickRatioConversionTest(9) {}

contract TickRatioConversionTest10 is TickRatioConversionTest(10) {}