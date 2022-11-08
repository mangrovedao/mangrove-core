// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// pragma experimental ABIEncoderV2;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";

import {Test2} from "mgv_lib/Test2.sol";

contract MgvOracleForInternal is MgvOracle {
  constructor(address _governance, address _initialMutator) MgvOracle(_governance, _initialMutator) {}

  //Only to test authOnly, which is an internal call
  function _authOnly() public view {
    authOnly();
  }

  //To get mutator, used to get "setMutator". MgvOracle has no read for mutator
  function getMutator() public view returns (address) {
    return mutator;
  }

  //To get gasprice. Used to test "setGasprice" without using "read" from MgvOracle
  function getGasprice() public view returns (uint) {
    return lastReceivedGasPrice;
  }

  //To get density. Used to test "setDensity" without using "read" from MgvOracle
  function getDensity() public view returns (uint) {
    return lastReceivedDensity;
  }
}

// In these tests, the testing contract is the market maker.
contract MgvOracleTest is Test2 {
  // Same events as in MgvOracle, needed to test that the events gets emitted
  event SetGasprice(uint gasPrice);
  event SetDensity(uint density);

  function test_authOnly() public {
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal( address(0), address(0));

    //does not revert
    mgvOracle._authOnly();

    address governance = freshAddress("governance");
    mgvOracle = new MgvOracleForInternal( governance, address(0));

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle._authOnly();

    vm.prank(governance);
    mgvOracle._authOnly(); // does not revert

    vm.prank(address(mgvOracle));
    mgvOracle._authOnly(); // does not revert
  }

  function test_setMutator() public {
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal( address(0), address(0));

    assertEq(mgvOracle.getMutator(), address(0), "mutator should not be set yet");

    address mutator = freshAddress("mutator");
    mgvOracle.setMutator(mutator);

    assertEq(mgvOracle.getMutator(), mutator, "mutator should be set");
  }

  function test_setGasPrice() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator);

    assertEq(mgvOracle.getGasprice(), 0, "gas should not be set yet");

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle.setGasPrice(20);

    vm.startPrank(governance);
    vm.expectEmit(false, false, false, true);
    emit SetGasprice(20);
    mgvOracle.setGasPrice(20);
    vm.stopPrank();

    assertEq(mgvOracle.getGasprice(), 20, "gas should be set");

    vm.startPrank(mutator);
    vm.expectEmit(false, false, false, true);
    emit SetGasprice(40);
    mgvOracle.setGasPrice(40);
    vm.stopPrank();

    assertEq(mgvOracle.getGasprice(), 40, "gas should be set");
  }

  function test_setDensity() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator);

    assertEq(mgvOracle.getDensity(), type(uint).max, "density should be set to max");

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle.setDensity(20);

    vm.startPrank(governance);
    vm.expectEmit(false, false, false, true);
    emit SetDensity(20);
    mgvOracle.setDensity(20);
    vm.stopPrank();

    assertEq(mgvOracle.getDensity(), 20, "density should be set by governance");

    vm.startPrank(mutator);
    vm.expectEmit(false, false, false, true);
    emit SetDensity(40);
    mgvOracle.setDensity(40);
    vm.stopPrank();

    assertEq(mgvOracle.getDensity(), 40, "density should be set by mutator");
  }

  function test_read() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator);

    vm.startPrank(governance);
    mgvOracle.setDensity(20);
    mgvOracle.setGasPrice(30);
    vm.stopPrank();

    (uint gas, uint density) = mgvOracle.read(address(0), address(0));

    assertEq(gas, 30, "gas should be 30");
    assertEq(density, 20, "density should be 20");
  }
}
