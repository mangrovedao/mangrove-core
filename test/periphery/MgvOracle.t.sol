// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// pragma experimental ABIEncoderV2;

import {MangroveTest} from "@mgv/test/lib/MangroveTest.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {Density, DensityLib} from "@mgv/lib/core/DensityLib.sol";
import "@mgv/src/core/MgvLib.sol";

import {Test2} from "@mgv/lib/Test2.sol";

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
  event SetDensity96X32(uint density96X32);

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

  function test_setDensity96X32() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 0);

    assertEq(Density.unwrap(mgvOracle.getDensity()), type(uint).max, "density should be set to max");

    vm.expectRevert("MgvOracle/unauthorized");
    mgvOracle.setDensity96X32(20 << 32);

    vm.startPrank(governance);
    vm.expectEmit(false, false, false, true);
    emit SetDensity96X32(DensityLib.from96X32(20 << 32).to96X32());
    mgvOracle.setDensity96X32(20 << 32);
    vm.stopPrank();

    assertEq(
      mgvOracle.getDensity().to96X32(), DensityLib.from96X32(20 << 32).to96X32(), "density should be set by governance"
    );

    vm.startPrank(mutator);
    vm.expectEmit(false, false, false, true);
    emit SetDensity96X32(DensityLib.from96X32(40 << 32).to96X32());
    mgvOracle.setDensity96X32(40 << 32);
    vm.stopPrank();

    assertEq(
      mgvOracle.getDensity().to96X32(), DensityLib.from96X32(40 << 32).to96X32(), "density should be set by mutator"
    );
  }

  function test_read() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 0);

    vm.startPrank(governance);
    mgvOracle.setDensity96X32(20 << 32);
    mgvOracle.setGasPrice(30);
    vm.stopPrank();

    (uint gas, Density density) = mgvOracle.read(OLKey(address(0), address(0), 0));

    assertEq(gas, 30, "gas should be 30");
    assertEq(density.to96X32(), DensityLib.from96X32(20 << 32).to96X32(), "density should be 20");
  }

  function test_set_density_96X32() public {
    address governance = freshAddress("governance");
    address mutator = freshAddress("mutator");
    MgvOracleForInternal mgvOracle = new MgvOracleForInternal(governance, mutator, 0);

    uint ceiling = 2 ** (96 + 32) - 1;

    // check no revert
    vm.prank(governance);
    mgvOracle.setDensity96X32(ceiling);

    vm.expectRevert("MgvOracle/config/density96X32/wrong");
    vm.prank(governance);
    mgvOracle.setDensity96X32(ceiling + 1);
  }
}
