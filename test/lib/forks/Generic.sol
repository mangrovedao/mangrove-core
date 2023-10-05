// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Script, console, stdJson} from "@mgv/forge-std/Script.sol";
import {ToyENS} from "@mgv/lib/ToyENS.sol";

/* A record entry in an addresses JSON file */
struct Record {
  address addr;
  string name;
}

struct MgvConfig {
  string[] addresses_paths;
  string deployment_addresses_path;
}

/* 
Note: when you add a *Fork contract, to have it available in deployment scripts,
remember to add it to the initialized forks in Deployer.sol.*/
contract GenericFork is Script {
  uint public INTERNAL_FORK_ID;
  uint public CHAIN_ID;
  string public NAME = "genericName";
  string public NETWORK = "genericNetwork"; // common network name, used as <NETWORK>.json filename
  uint public BLOCK_NUMBER;

  // context addresses (aave, gas update bot, etc)
  ToyENS context;
  // addresses we deploy
  ToyENS deployed;

  constructor() {
    context = new ToyENS();
    vm.makePersistent(address(context));
    deployed = new ToyENS();
    vm.makePersistent(address(deployed));
  }

  // this contract can be used in an already-forked environment, in which case
  // methods such as roll(), select() are unusable (since we don't have a handle on the current fork).
  bool readonly = false;

  /* get/set addresses, passthrough to context/deployed ToyENS instances */

  function set(string memory name, address addr) public {
    require(context._addrs(name) == address(0), "Fork: context addresses cannot be changed.");
    deployed.set(name, addr);
    label(addr, name);
  }

  function getNoRevert(string memory name) public view returns (address payable addr) {
    addr = payable(context._addrs(name));
    if (addr == address(0)) {
      return payable(deployed._addrs(name));
    }
  }

  function get(string memory name) public view returns (address payable addr) {
    addr = getNoRevert(name);
    if (addr == address(0)) {
      revert(
        string.concat(
          "Fork::get(string name)",
          name,
          ": no contract found for name argument, either in context nor in deployed addresses. Check the appropriate context/<chain>.json and deployed/<chain>.json, and make sure you are doing fork.set(name,address) for all your deployed contracts."
        )
      );
    }
  }

  function has(string memory name) public view returns (bool) {
    return getNoRevert(name) != address(0);
  }

  function allDeployed() public view returns (string[] memory, address[] memory) {
    return deployed.all();
  }

  /* Read addresses from JSON files */

  function addressesFile(string memory pathFromRoot, string memory category, string memory suffix)
    public
    view
    returns (string memory)
  {
    return string.concat(vm.projectRoot(), "/", pathFromRoot, category, "/", NETWORK, suffix, ".json");
  }

  function readMgvConfig() public view returns (MgvConfig memory) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/mgvConfig.json");
    string memory json = vm.readFile(path);
    bytes memory parsedJson = vm.parseJson(json);
    MgvConfig memory config = abi.decode(parsedJson, (MgvConfig));
    return config;
  }

  function addressesFileDeployment(string memory category, string memory suffix) public view returns (string memory) {
    MgvConfig memory config = readMgvConfig();
    return addressesFile(config.deployment_addresses_path, category, suffix);
  }

  function addressesFileDeployment(string memory category) public view returns (string memory) {
    MgvConfig memory config = readMgvConfig();
    return addressesFile(config.deployment_addresses_path, category, "");
  }

  function readAddresses(string memory category) internal returns (Record[] memory) {
    Record[] memory envRecords = readEnvAddresses(category);
    bool readMgvConfigPaths = vm.envOr("MGV_READ_ADDRESSES_PATHS", true);
    if (!readMgvConfigPaths) {
      return envRecords;
    }

    Record[] memory mgvConfigRecords = new Record[](0);
    if (readMgvConfigPaths) {
      mgvConfigRecords = readMgvConfigAddresses(category);
    }

    Record[] memory allRecords = new Record[](envRecords.length + mgvConfigRecords.length);
    for (uint i = 0; i < envRecords.length; i++) {
      allRecords[i] = envRecords[i];
    }
    for (uint i = 0; i < mgvConfigRecords.length; i++) {
      allRecords[envRecords.length + i] = mgvConfigRecords[i];
    }

    return allRecords;
  }

  function readEnvAddresses(string memory category) internal returns (Record[] memory) {
    string memory defaultPath = "";
    string memory paths = vm.envOr("MGV_ADDRESSES_PATHS", defaultPath);
    if (bytes(paths).length > 0) {
      bytes memory encodedPaths = vm.parseJson(paths);
      return readAddressesFromJson(encodedPaths, category);
    } else {
      return (new Record[](0));
    }
  }

  function readMgvConfigAddresses(string memory category) internal returns (Record[] memory) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/mgvConfig.json");
    string memory paths = vm.readFile(path);
    if (bytes(paths).length > 0) {
      bytes memory encodedPaths = vm.parseJson(paths);
      return readAddressesFromJson(encodedPaths, category);
    } else {
      return (new Record[](0));
    }
  }

  function readAddressesFromJson(bytes memory encodedPaths, string memory category) internal returns (Record[] memory) {
    MgvConfig memory mgvConfig = abi.decode(encodedPaths, (MgvConfig));
    Record[][] memory allRecords = new Record[][](mgvConfig.addresses_paths.length);
    for (uint i = 0; i < mgvConfig.addresses_paths.length; i++) {
      string memory pathFromRoot = addressesFile(mgvConfig.addresses_paths[i], category, "");
      Record[] memory envRecords = readAddressesFromFileName(pathFromRoot);
      if (envRecords.length > 0) {
        allRecords[i] = envRecords;
      }
    }
    uint totalLength = 0;
    for (uint i = 0; i < allRecords.length; i++) {
      totalLength += allRecords[i].length;
    }
    Record[] memory fullRecords = new Record[](totalLength);
    uint index = 0;
    for (uint i = 0; i < allRecords.length; i++) {
      for (uint j = 0; j < allRecords[i].length; j++) {
        fullRecords[index] = allRecords[i][j];
        index++;
      }
    }
    return fullRecords;
  }

  function readAddressesFromFileName(string memory fileName) internal returns (Record[] memory) {
    try vm.readFile(fileName) returns (string memory addressesRaw) {
      if (bytes(addressesRaw).length == 0) {
        return (new Record[](0));
      }
      try vm.parseJson(addressesRaw) returns (bytes memory jsonBytes) {
        try (new Parser()).parseJsonBytes(jsonBytes) returns (Record[] memory envRecords) {
          return envRecords;
        } catch {
          revert(string.concat("Fork: JSON to Record[] parsing error on file ", fileName));
        }
      } catch {
        revert(string.concat("Fork: JSON parsing error on file ", fileName));
      }
    } catch {
      console.log("Fork: cannot read deployment file %s. Ignoring.", fileName);
    }

    // return empty record array by default
    return (new Record[](0));
  }

  /* Select/modify current fork
     ! Does not impact context/deployed mappings !
  */

  function checkCanWrite() internal view {
    require(!readonly, "Cannot manipulate current fork");
  }

  function roll() public {
    checkCanWrite();
    vm.rollFork(INTERNAL_FORK_ID);
  }

  function roll(uint blockNumber) public {
    checkCanWrite();
    vm.rollFork(INTERNAL_FORK_ID, blockNumber);
  }

  function select() public {
    checkCanWrite();
    vm.selectFork(INTERNAL_FORK_ID);
  }

  function setUp() public virtual {
    // label ToyENS instances
    label(address(context), "Context ENS");
    label(address(deployed), "Deployed ENS");

    // check that we are not a GenericFork instance
    if (CHAIN_ID == 0) {
      revert("No fork selected: you should pick a subclass of GenericFork with a nonzero CHAIN_ID.");
    }

    // survive all fork operations
    vm.makePersistent(address(this));

    // read addresses from JSON files
    Record[] memory envRecords = readAddresses("context");
    for (uint i = 0; i < envRecords.length; i++) {
      context.set(envRecords[i].name, envRecords[i].addr);
      label(envRecords[i].addr, envRecords[i].name);
    }
    envRecords = readAddresses("deployed");
    for (uint i = 0; i < envRecords.length; i++) {
      set(envRecords[i].name, envRecords[i].addr);
    }

    // If a remote ToyENS is found, import its envRecords.
    ToyENS remoteEns = ToyENS(address(bytes20(hex"decaf0")));
    if (address(remoteEns).code.length > 0) {
      (string[] memory names, address[] memory addrs) = remoteEns.all();
      for (uint i = 0; i < names.length; i++) {
        set(names[i], addrs[i]);
      }
    }

    // if already forked, ignore BLOCK_NUMBER & don't re-fork
    if (block.chainid != CHAIN_ID) {
      if (BLOCK_NUMBER == 0) {
        // 0 means latest
        INTERNAL_FORK_ID = vm.createFork(vm.rpcUrl(NAME));
      } else {
        INTERNAL_FORK_ID = vm.createFork(vm.rpcUrl(NAME), BLOCK_NUMBER);
      }

      vm.selectFork(INTERNAL_FORK_ID);

      if (block.chainid != CHAIN_ID) {
        revert(
          string.concat("Chain id should be ", vm.toString(CHAIN_ID), " (", NAME, "), is ", vm.toString(block.chainid))
        );
      }
    } else {
      readonly = true;
    }
  }

  // append current fork name to address & label it
  function label(address addr, string memory str) internal {
    vm.label(addr, string.concat(str, " (", NAME, ")"));
  }
}

/* Gadget contract which parses given bytes as Record[]. 
   Useful for catching abi.decode errors. */
contract Parser {
  function parseJsonBytes(bytes memory jsonBytes) external pure returns (Record[] memory) {
    return abi.decode(jsonBytes, (Record[]));
  }
}
