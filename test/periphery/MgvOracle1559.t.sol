// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// pragma experimental ABIEncoderV2;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {MgvOracle1559} from "mgv_src/periphery/MgvOracle1559.sol";
import {console} from "forge-std/console.sol";

import {Test2} from "mgv_lib/Test2.sol";

// In these tests, the testing contract is the market maker.
contract MgvOracleTest is Test2 {
  // Same events as in MgvOracle, needed to test that the events gets emitted
  event SetGasprice(uint gasPrice);
  event SetDensity(uint density);

  address governance;
  address mutator;
  MgvOracle1559 oracle;

  function setUp() public {
    governance = freshAddress("governance");
    mutator = freshAddress("mutator");
    oracle = new MgvOracle1559(governance,mutator);
  }

  function test_setGasPrice() public {
    vm.expectRevert("MgvOracle1559/noSetGasPrice");
    vm.prank(governance);
    oracle.setGasPrice(1);
  }

  function test_read_simple() public {
    vm.startPrank(governance);
    oracle.updatePriorityFee();
    vm.stopPrank();

    (uint gas,) = oracle.read(address(0), address(0));

    assertEq(gas, tx.gasprice, "gas should be current tx gasprice");
  }

  function test_read_custom(uint priorityFee, uint basefee1, uint basefee2, uint gasScaling) public {
    vm.fee(basefee1);

    vm.startPrank(governance);
    oracle.setPriorityFee(priorityFee);
    oracle.setGasScaling(gasScaling);
    vm.stopPrank();

    vm.fee(basefee2);

    try oracle.read(address(0), address(0)) returns (uint gasprice, uint) {
      uint expectedGasprice = (basefee2 + priorityFee) * gasScaling / 10_000;
      assertEq(gasprice, expectedGasprice, "incorrect gasprice");
    } catch {
      // ignore read errors
    }
  }
}
