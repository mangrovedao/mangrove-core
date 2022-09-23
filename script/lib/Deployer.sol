// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script2} from "mgv_test/lib/Script2.sol";
import {ToyENS} from "./ToyENS.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {MumbaiFork} from "mgv_test/lib/forks/Mumbai.sol";
import {LocalFork} from "mgv_test/lib/forks/Local.sol";

/* Writes deployments in 2 ways:
   1. In a json file. Easier to write one directly than to parse&transform
   foundry broadcast log files.
   2. In a toy ENS instance. Useful for testing when the server & testingbi script
   are both spawned in-process. Holds additional info on the contracts (whether
   it's a token). In the future, could be either removed (in favor of a
   file-based solution), or expanded (if an onchain addressProvider appears).

   How to use:
   1. Inherit Deployer.
   2. Write a innerRun() function that does all the work and can be called by other scripts.
   3. Write a standalone run() function that will be called by forge script. Call outputDeployment() at the end of run() if you deployed any contract.

   Do not inherit other deployer scripts! Just instantiate them and call their
   .innerRun() function;
*/
abstract contract Deployer is Script2 {
  // singleton Fork so all deploy scripts talk to the same backend
  // singleton method used for fork, so constructor-modified state is kept (just doing vm.etch forgets that state diff)
  GenericFork fork = GenericFork(singleton("Deployer:Fork"));
  // This remote ENS cannot be set from the deployment script because anvil does not support cheatcodes. The client will use anvil_setCode at that address.
  ToyENS remoteEns = ToyENS(address(bytes20(hex"decaf0")));

  bool writeDeploy; // whether to write a .json file with updated addresses
  address broadcaster; // who will broadcast

  constructor() {
    vm.label(address(fork), "Deployer:Fork");
    vm.label(address(remoteEns), "Remote ENS");

    // depending on which fork the script is running on, choose whether to write the addresses to a file, get the right fork contract, and name the current network.
    if (singleton("Deployer:Fork") == address(0)) {
      if (block.chainid == 80001) {
        fork = new MumbaiFork();
      } else if (block.chainid == 127) {
        fork = new PolygonFork();
      } else if (block.chainid == 31337) {
        fork = new LocalFork();
      } else {
        revert(
          string.concat(
            "Unknown chain id ",
            vm.toString(block.chainid),
            ", cannot deploy."
          )
        );
      }

      singleton("Deployer:Fork", address(fork));
      fork.setUp();
    } else {
      fork = GenericFork(singleton("Deployer:Fork"));
    }

    try vm.envBool("WRITE_DEPLOY") returns (bool _writeDeploy) {
      writeDeploy = _writeDeploy;
    } catch {}
  }

  // broadcast using a broadcasting address in the descending prio order:
  // * <NETWORK>_PRIVATE_KEY env var's associated address
  // * --sender
  // * --private-key (or 1st of --private-keys)'s associated address
  // * forge default sending address
  function broadcast() public {
    /* Memoize broadcaster. Cannot just do it in constructor because tx.origin for script constructors is not the same as for function calls */
    if (broadcaster == address(0)) {
      broadcaster = tx.origin;
      // If sender is not forge's default sender, ignore env var config
      // Otherwise, load <NETWORK>_PRIVATE_KEY (if it exists)
      if (broadcaster == 0x00a329c0648769A73afAc7F9381E08FB43dBEA72) {
        string memory envVar = string.concat(
          simpleCapitalize(fork.NAME()),
          "_PRIVATE_KEY"
        );
        try vm.envUint(envVar) returns (uint key) {
          broadcaster = vm.rememberKey(key);
        } catch {}
      }
    }
    vm.broadcast(broadcaster);
  }

  // buffer for output file
  string out;

  function outputDeployment() internal {
    (string[] memory names, address[] memory addrs) = fork.allDeployed();

    if (address(remoteEns).code.length > 0) {
      broadcast();
      remoteEns.set(names, addrs);
    }

    out = "";
    line("[");
    for (uint i = 0; i < names.length; i++) {
      bool end = i + 1 == names.length;
      line("  {");
      line(string.concat('    "address": "', vm.toString(addrs[i]), '",'));
      line(string.concat('    "name": "', names[i], '"'));
      line(end ? "  }" : "  },");
    }
    line("]");
    vm.writeFile(
      fork.addressesFile(
        "deployed",
        string.concat("-", vm.toString(block.timestamp), ".backup")
      ),
      out
    );
    if (writeDeploy) {
      vm.writeFile(fork.addressesFile("deployed"), out);
    }
  }

  function line(string memory s) internal {
    out = string.concat(out, s, "\n");
  }
}
