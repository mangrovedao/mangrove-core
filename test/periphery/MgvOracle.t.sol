// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// pragma experimental ABIEncoderV2;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {Density, DensityLib} from "mgv_lib/DensityLib.sol";
import {OL} from "mgv_src/MgvLib.sol";

import {Test2} from "mgv_lib/Test2.sol";

contract MgvOracleForInternal is MgvOracle {
  constructor(address _governance, address _initialMutator, uint _initialGasPrice)
    MgvOracle(_governance, _initialMutator, _initialGasPrice)
  {}

  //Only to test authOnly, which is an internal call
  function _authOnly() public view {
    authOnly();
  }

  //To get governance, used to get "setGovernance". MgvOracle has no read for governance
  function getGovernance() public view returns (address) {
    return governance;
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
  function getDensity() public view returns (Density) {
    return lastReceivedDensity;
  }
}

// In these tests, the testing contract is the market maker.
contract MgvOracleTest is Test2 {
  // Same events as in MgvOracle, needed to test that the events gets emitted
  event SetGasprice(uint gasPrice);
  event SetDensityFixed(uint densityFixed);

  function test_authOnly() public {
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal( address(0), address(0), 0);

    //does not revert
    mgvOracle._authOnly();

    address governance = freshAddress("governance");
    mgvOracle = new MgvOracleForInternal( governance, address(0), 0);

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle._authOnly();

    vm.prank(governance);
    mgvOracle._authOnly(); // does not revert

    vm.prank(address(mgvOracle));
    mgvOracle._authOnly(); // does not revert
  }

  function test_setGovernance() public {
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal( address(0), address(0), 0);

    assertEq(mgvOracle.getGovernance(), address(0), "governance should not be set yet");

    address governance = freshAddress("governance");
    mgvOracle.setGovernance(governance);

    assertEq(mgvOracle.getGovernance(), governance, "governance should be set");
  }

  function test_setMutator() public {
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal( address(0), address(0), 0);

    assertEq(mgvOracle.getMutator(), address(0), "mutator should not be set yet");

    address mutator = freshAddress("mutator");
    mgvOracle.setMutator(mutator);

    assertEq(mgvOracle.getMutator(), mutator, "mutator should be set");
  }

  function test_setGasPrice() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 1);

    assertEq(mgvOracle.getGasprice(), 1, "gas should be set to the initial value");

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

  function test_setDensityFixed() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 0);

    assertEq(Density.unwrap(mgvOracle.getDensity()), type(uint).max, "density should be set to max");

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle.setDensityFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS);

    vm.startPrank(governance);
    vm.expectEmit(false, false, false, true);
    emit SetDensityFixed(DensityLib.fromFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS).toFixed());
    mgvOracle.setDensityFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS);
    vm.stopPrank();

    assertEq(
      mgvOracle.getDensity().toFixed(),
      DensityLib.fromFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS).toFixed(),
      "density should be set by governance"
    );

    vm.startPrank(mutator);
    vm.expectEmit(false, false, false, true);
    emit SetDensityFixed(DensityLib.fromFixed(40 << DensityLib.FIXED_FRACTIONAL_BITS).toFixed());
    mgvOracle.setDensityFixed(40 << DensityLib.FIXED_FRACTIONAL_BITS);
    vm.stopPrank();

    assertEq(
      mgvOracle.getDensity().toFixed(),
      DensityLib.fromFixed(40 << DensityLib.FIXED_FRACTIONAL_BITS).toFixed(),
      "density should be set by mutator"
    );
  }

  function test_read() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 0);

    vm.startPrank(governance);
    mgvOracle.setDensityFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS);
    mgvOracle.setGasPrice(30);
    vm.stopPrank();

    (uint gas, Density density) = mgvOracle.read(OL(address(0), address(0), 0));

    assertEq(gas, 30, "gas should be 30");
    assertEq(
      density.toFixed(), DensityLib.fromFixed(20 << DensityLib.FIXED_FRACTIONAL_BITS).toFixed(), "density should be 20"
    );
  }
}
