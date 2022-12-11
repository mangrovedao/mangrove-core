// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

contract MangroveDeployerTest is Deployer, Test2 {
  MangroveDeployer mgvDeployer;
  address chief;
  uint gasprice;
  uint gasmax;

  function setUp() public {
    mgvDeployer = new MangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    mgvDeployer.innerRun(chief, gasprice, gasmax);
  }

  function test_toy_ens_has_addresses() public {
    assertEq(fork.get("Mangrove"), address(mgvDeployer.mgv()));
    assertEq(fork.get("MgvReader"), address(mgvDeployer.reader()));
    assertEq(fork.get("MgvCleaner"), address(mgvDeployer.cleaner()));
    assertEq(fork.get("MgvOracle"), address(mgvDeployer.oracle()));
  }

  function test_contracts_instantiated_correctly() public {
    address outbound_tkn = freshAddress("outbound_tkn");
    address inbound_tkn = freshAddress("inbound_tkn");

    // Mangrove - verify expected values have been passed in
    Mangrove mgv = mgvDeployer.mgv();
    assertEq(mgv.governance(), chief);
    (MgvStructs.GlobalPacked cfg,) = mgv.config(address(0), address(0));
    assertEq(cfg.gasprice(), gasprice);
    assertEq(cfg.gasmax(), gasmax);

    // Reader - verify mgv is used
    MgvReader reader = mgvDeployer.reader();
    vm.expectCall(address(mgv), abi.encodeCall(mgv.config, (outbound_tkn, inbound_tkn)));
    reader.getProvision(outbound_tkn, inbound_tkn, 0, 0);

    // Cleaner - verify mgv is used
    MgvCleaner cleaner = mgvDeployer.cleaner();
    uint[4][] memory targets = wrap_dynamic([uint(0), 0, 0, 0]);
    vm.expectCall(
      address(mgv), abi.encodeCall(mgv.snipesFor, (outbound_tkn, inbound_tkn, targets, true, address(this)))
    );
    vm.expectRevert("mgv/inactive");
    cleaner.collect(outbound_tkn, inbound_tkn, targets, true);

    // Oracle - verify expected values have been passed in. We read from storage slots - alternatively, we should poke admin methods to verify correct setup.
    MgvOracle oracle = mgvDeployer.oracle();
    bytes32 oracleGovernance = vm.load(address(oracle), bytes32(uint(0)));
    assertEq(chief, address(uint160(uint(oracleGovernance))));
    bytes32 oracleMutator = vm.load(address(oracle), bytes32(uint(1)));
    assertEq(chief, address(uint160(uint(oracleMutator))));
  }
}
