// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import {console, stdJson} from "forge-std/Script.sol";
import {Script2} from "mgv_test/lib/Script2.sol";
import {ToyENS} from "./ToyENS.sol";

struct Record {
  address addr;
  bool isToken;
  string name;
}

/* Writes deployments in 2 ways:
   1. In a json file. Easier to write one directly than to parse&transform
   foundry broadcast log files.
   2. In a toy ENS instance. Useful for testing when the server & testing script
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
  ToyENS ens; // singleton local ens instance
  ToyENS remoteEns; // out-of-band agreed upon toy ens address
  mapping(uint => string) chainkeys; // out-of-band agreed upon chain names
  // deployment folder to write to

  using stdJson for string;

  constructor() {
    // enforce singleton ENS, so all deploys can be collected in outputDeployment
    // otherwise Deployer scripts would need to inherit from one another
    // which would prevent deployer script composition
    ens = ToyENS(address(bytes20(hex"decaf1")));
    remoteEns = ToyENS(address(bytes20(hex"decaf0")));

    chainkeys[80001] = "maticmum";
    chainkeys[127] = "polygon";
    // chainkeys[31337] = "local"; // useful for debugging, but deactivated for now

    if (address(ens).code.length == 0) {
      vm.etch(address(ens), address(new ToyENS()).code);
      Record[] memory records = readAddresses();
      for (uint i = 0; i < records.length; i++) {
        ens.set(records[i].name, records[i].addr, records[i].isToken);
      }
    }
  }

  function readAddresses() internal returns (Record[] memory) {
    try vm.readFile(file()) returns (string memory addressesRaw) {
      if (bytes(addressesRaw).length == 0) {
        // allow empty file
        return (new Record[](0));
      }
      try vm.parseJson(addressesRaw) returns (bytes memory jsonBytes) {
        /* We want to catch an abi.decode errors. Only way is through a call.
           For unknown reasons this.call does not work.
           So we create a gadget contract.  */
        try (new Parser()).parseJsonBytes(jsonBytes) returns (
          Record[] memory records
        ) {
          return records;
        } catch {
          revert(
            string.concat("Deployer/error JSON as Record[]. File: ", file())
          );
        }
      } catch {
        revert(
          string.concat("Deployer/error parsing file as JSON. File: ", file())
        );
      }
    } catch {
      console.log("Deployer/cannot read file. Ignoring. File: %s", file());
    }

    // return empty record array by default
    return (new Record[](0));
  }

  function file() internal view returns (string memory) {
    return
      string.concat(
        vm.projectRoot(),
        "/addresses/",
        chainkeys[block.chainid],
        ".json"
      );
  }

  function outputDeployment() internal {
    (string[] memory names, address[] memory addrs, bool[] memory isToken) = ens
      .all();

    // toy ens is set, use it
    if (address(remoteEns).code.length > 0) {
      vm.broadcast();
      remoteEns.set(names, addrs, isToken);
    }

    // known chain, write deployment file
    if (bytes(chainkeys[block.chainid]).length != 0) {
      vm.writeFile(file(), ""); // clear file
      line("[");
      for (uint i = 0; i < names.length; i++) {
        bool end = i + 1 == names.length;
        line("  {");
        line(string.concat('    "address": "', vm.toString(addrs[i]), '",'));
        line(string.concat('    "isToken": ', vm.toString(isToken[i]), ""));
        line(string.concat('    "name": "', names[i], '"'));
        line(string.concat("  }", end ? "" : ","));
      }
      line("]");
    } else {
      console.log("Deployer: Unknown chain. Will not write an addresses file.");
    }
  }

  function line(string memory s) internal {
    vm.writeLine(file(), s);
  }
}

/* Gadget contract which parses given bytes as Record[]. 
   Useful for catching abi.decode errors. */
contract Parser {
  function parseJsonBytes(bytes memory jsonBytes)
    external
    pure
    returns (Record[] memory)
  {
    return abi.decode(jsonBytes, (Record[]));
  }
}
