// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script2} from "mgv_lib/Script2.sol";
import {ToyENS} from "mgv_lib/ToyENS.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {MumbaiFork} from "mgv_test/lib/forks/Mumbai.sol";
import {LocalFork} from "mgv_test/lib/forks/Local.sol";
import {console2 as console} from "forge-std/console2.sol";

address constant ANVIL_DEFAULT_FIRST_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

/* Writes deployments in 2 ways:
   1. In a json file. Easier to write one directly than to parse&transform
   foundry broadcast log files.
   2. In a toy Ethereum Name Service (ENS) instance. Useful for testing when the server & testing script
   are both spawned in-process. Holds additional info on the contracts (whether
   it's a token). In the future, could be either removed (in favor of a
   file-based solution), or expanded (if an onchain addressProvider appears).

   How to use:
   1. Inherit Deployer.
   2. Write a innerRun() function that does all the work and can be called by other scripts.
   3. Write a standalone run() function that will be called by forge script. Call outputDeployment() at the end of run() if you deployed any contract.

   Do not inherit other deployer scripts! Just instantiate them and call their
   .innerRun() function;*/
abstract contract Deployer is Script2 {
  // singleton Fork so all deploy scripts talk to the same backend
  // singleton method used for fork, so constructor-modified state is kept (just doing vm.etch forgets that state diff)
  GenericFork fork = GenericFork(singleton("Deployer:Fork"));
  // This remote ENS cannot be set from the deployment script because anvil does not support cheatcodes. The client will use anvil_setCode at that address.
  ToyENS remoteEns = ToyENS(address(bytes20(hex"decaf0")));

  bool writeDeploy; // whether to write a .json file with updated addresses
  address _broadcaster; // who will broadcast
  bool forMultisig; // whether the deployment is intended to be broadcast or given to a multisig.
  bytes32 salt; // salt used for create2 deployments

  constructor() {
    vm.label(address(fork), "Deployer:Fork");
    vm.label(address(remoteEns), "Remote ENS");

    // detect if we've already created a fork -- the singleton method works as an inter-contract storage used for communication
    if (singleton("Deployer:Fork") == address(0)) {
      // depending on which fork the script is running on, choose whether to write the addresses to a file, get the right fork contract, and name the current network.
      if (block.chainid == 80001) {
        fork = new MumbaiFork();
      } else if (block.chainid == 137) {
        fork = new PolygonFork();
      } else if (block.chainid == 31337) {
        fork = new LocalFork();
      } else {
        revert(string.concat("Unknown chain id ", vm.toString(block.chainid), ", cannot deploy."));
      }

      if (address(remoteEns).code.length == 0 && ANVIL_DEFAULT_FIRST_ACCOUNT.balance >= 1000 ether) {
        deployRemoteToyENS();
      }

      singleton("Deployer:Fork", address(fork));
      fork.setUp();
    } else {
      fork = GenericFork(singleton("Deployer:Fork"));
    }

    try vm.envBool("WRITE_DEPLOY") returns (bool writeDeploy_) {
      writeDeploy = writeDeploy_;
    } catch {}

    forMultisig = vm.envOr("FOR_MULTISIG", false);

    // use the given SALT's bytes as salt
    // prevent truncation
    bytes memory saltBytes = bytes(vm.envOr("SALT", string("")));
    if (saltBytes.length > 32) {
      revert("SALT env var length must be =< 32 bytes");
    }

    salt = bytes32(saltBytes);
  }

  // broadcast using forge-provided tx.origin; or if default try to use <NETWORK>_PRIVATE_KEY env var's associated address.
  // In practice, this means you can set your deployer key MUMBAI_PRIVATE_KEY in your .env, and you can override that using --private-key <pk>
  function broadcast() public {
    vm.broadcast(broadcaster());
  }

  function startBroadcast() public {
    vm.startBroadcast(broadcaster());
  }

  function stopBroadcast() public {
    // convenience
    vm.stopBroadcast();
  }

  // compute & memoize the current broadcaster address
  function broadcaster() public returns (address) {
    /* Memoize _broadcaster. Cannot just do it in constructor because tx.origin for script constructors does not depend on additional CLI args */
    if (_broadcaster == address(0)) {
      // In the default case, forge sets the broadcaster to be tx.origin.
      // Using msg.sender would not work since we don't know how deep in the callstack we are.
      _broadcaster = tx.origin;
      // there are two possible default tx.origin depending on foundry version
      if (_broadcaster == 0x00a329c0648769A73afAc7F9381E08FB43dBEA72 || _broadcaster == DEFAULT_SENDER) {
        // we interpret the BROADCASTER variable because --sender fails immediately if it is a contract
        // has precedence over *_PRIVATE_KEY
        if (envHas("BROADCASTER")) {
          _broadcaster = envAddressOrName("BROADCASTER");
        } else {
          string memory pkEnvVar = string.concat(simpleCapitalize(fork.NAME()), "_PRIVATE_KEY");
          try vm.envUint(pkEnvVar) returns (uint key) {
            _broadcaster = vm.rememberKey(key);
          } catch {
            console.log("%s not found or not parseable as uint, using default broadcast sender", pkEnvVar);
          }
        }
      }
    }
    return _broadcaster;
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
    string memory latestBackupFile = fork.addressesFile("deployed.backup", "-latest");
    string memory timestampedBackupFile =
      fork.addressesFile("deployed.backup", string.concat("-", vm.toString(block.timestamp), ".backup"));
    string memory mainFile = fork.addressesFile("deployed");
    vm.writeFile(latestBackupFile, out);
    vm.writeFile(timestampedBackupFile, out);
    if (writeDeploy) {
      vm.writeFile(mainFile, out);
    } else {
      console.log(
        "\u001b[33m Warning \u001b[0m You have not set WRITE_DEPLOY=true. \n The main deployment file will not be updated. To update it after running this script, copy %s to %s",
        latestBackupFile,
        mainFile
      );
    }
  }

  function line(string memory s) internal {
    out = string.concat(out, s, "\n");
  }

  function envAddressOrName(string memory envVar) internal view returns (address payable) {
    try vm.envAddress(envVar) returns (address addr) {
      return payable(addr);
    } catch {
      return fork.get(vm.envString(envVar));
    }
  }

  function envHas(string memory envVar) internal view returns (bool) {
    try vm.envString(envVar) {
      return true;
    } catch {
      return false;
    }
  }

  // FFI to `cast rpc setCode` in order to setup a ToyENS at a known address
  function deployRemoteToyENS() internal {
    string[] memory inputs = new string[](5);
    inputs[0] = "cast";
    inputs[1] = "rpc";
    inputs[2] = "hardhat_setCode";
    inputs[3] = vm.toString(address(remoteEns));
    inputs[4] = vm.toString(address(new ToyENS()).code);
    bytes memory resp = vm.ffi(inputs);
    if (keccak256(resp) != keccak256("null")) {
      console.log(string(resp));
      revert("Unexpected response from `cast rpc hardhat_setCode`");
    }
    console.log("Deployed remote ToyENS");
  }
}
