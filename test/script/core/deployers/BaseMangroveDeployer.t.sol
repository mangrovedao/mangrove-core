// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";

import {Test2, Test} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader, Market} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

/**
 * Base test suite for [Chain]MangroveDeployer scripts
 */
abstract contract BaseMangroveDeployerTest is Deployer, Test2 {
  MangroveDeployer mgvDeployer;
  address chief;
  uint gasprice;
  uint gasmax;
  address gasbot;

  function test_toy_ens_has_addresses() public {
    assertEq(fork.get("Mangrove"), address(mgvDeployer.mgv()));
    assertEq(fork.get("MgvReader"), address(mgvDeployer.reader()));
    assertEq(fork.get("MgvOracle"), address(mgvDeployer.oracle()));
  }

  function test_contracts_instantiated_correctly(uint tickSpacing) public {
    OLKey memory olKey = OLKey(freshAddress("oubtound_tkn"), freshAddress("inbound_tkn"), tickSpacing);

    // Oracle - verify expected values have been passed in. We read from storage slots - alternatively, we should poke admin methods to verify correct setup.
    MgvOracle oracle = mgvDeployer.oracle();
    bytes32 oracleGovernance = vm.load(address(oracle), bytes32(uint(0)));
    assertEq(chief, address(uint160(uint(oracleGovernance))));
    bytes32 oracleMutator = vm.load(address(oracle), bytes32(uint(1)));
    assertEq(gasbot, address(uint160(uint(oracleMutator))));
    (uint gasprice_, Density density_) = oracle.read(olKey);
    assertEq(gasprice, gasprice_);
    assertEq(type(uint).max, Density.unwrap(density_));

    // Mangrove - verify expected values have been passed in
    IMangrove mgv = mgvDeployer.mgv();
    assertEq(mgv.governance(), chief);
    Global cfg = mgv.global();
    assertEq(cfg.gasmax(), gasmax);
    assertEq(cfg.monitor(), address(oracle), "monitor should be set to oracle");
    assertTrue(cfg.useOracle(), "useOracle should be set");

    // Reader - verify mgv is used
    MgvReader reader = mgvDeployer.reader();
    vm.expectCall(address(mgv), abi.encodeCall(mgv.config, (olKey)));
    reader.getProvision(olKey, 0, 0);
  }
}
