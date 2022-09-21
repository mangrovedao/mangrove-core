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
   2. Write a deploy() function that does all the deployment and can be called by other deployers.
   3. Write a standalone run() function that will be called by forge script. Call outputDeployment() at the end of run() if you deployed any contract.

   Do not inherit other deployer scripts! Just instantiate them and call their
   .deploy() function;
*/
abstract contract Deployer is Script2 {
  // singleton Fork so all deploy scripts talk to the same backend
  // singleton method used for fork, so constructor-modified state is kept (just doing vm.etch forgets that state diff)
  GenericFork fork = GenericFork(singleton("Deployer:Fork"));
  // This remote ENS cannot be set from the deployment script because anvil does not support cheatcodes. The client will use anvil_setCode at that address.
  ToyENS remoteEns = ToyENS(address(bytes20(hex"decaf0")));

  bool createFile; // whether to write a .json file with updated addresses

  constructor() {
    // depending on which fork the script is running on, choose whether to write the addresses to a file, get the right fork contract, and name the current network.
    if (singleton("Deployer:Fork") == address(0)) {
      createFile = true;
      if (block.chainid == 80001) {
        fork = new MumbaiFork();
      } else if (block.chainid == 127) {
        fork = new PolygonFork();
      } else if (block.chainid == 31337) {
        createFile = false;
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
  }

  string out;

  function outputDeployment() internal {
    (
      string[] memory names,
      address[] memory addrs
    ) = fork.allDeployed();

    if (address(remoteEns).code.length > 0) {
      vm.broadcast();
      remoteEns.set(names, addrs);
    }

    if (createFile) {
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
      vm.writeFile(fork.addressesFile("deployed"), out);
      vm.writeFile(
        fork.addressesFile(
          "deployed",
          string.concat("-", vm.toString(block.timestamp), ".backup")
        ),
        out
      );
    }
  }

  function line(string memory s) internal {
    out = string.concat(out, s, "\n");
  }
}
