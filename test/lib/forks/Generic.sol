// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "forge-std/Vm.sol";

contract GenericFork is Script {
  uint public INTERNAL_FORK_ID;
  uint public CHAIN_ID;
  string public NAME = "generic";
  uint public BLOCK_NUMBER;

  address public AAVE;
  address public APOOL;
  address public WETH;
  address public AUSDC;
  address public USDC;
  address public AWETH;
  address public DAI;
  address public ADAI;
  address public CDAI;
  address public CUSDC;
  address public CWETH;

  function roll() public {
    vm.rollFork(INTERNAL_FORK_ID);
  }

  function roll(uint blockNumber) public {
    vm.rollFork(INTERNAL_FORK_ID, blockNumber);
  }

  function select() public {
    vm.selectFork(INTERNAL_FORK_ID);
  }

  function setUp() public virtual {
    if (CHAIN_ID == 0) {
      revert(
        "No fork selected: you should pick a subclass of GenericFork with a nonzero CHAIN_ID."
      );
    }

    label(AAVE, "Aave");
    label(APOOL, "Aave Pool");
    label(WETH, "WETH");
    label(AUSDC, "AUSDC");
    label(USDC, "USDC");
    label(AWETH, "AWETH");
    label(DAI, "DAI");
    label(ADAI, "ADAI");
    label(CDAI, "CDAI");
    label(CUSDC, "CUSDC");
    label(CWETH, "CWETH");

    vm.makePersistent(address(this));

    if (BLOCK_NUMBER == 0) {
      // 0 means latest
      INTERNAL_FORK_ID = vm.createFork(vm.rpcUrl(NAME));
    } else {
      INTERNAL_FORK_ID = vm.createFork(vm.rpcUrl(NAME), BLOCK_NUMBER);
    }

    vm.selectFork(INTERNAL_FORK_ID);

    if (block.chainid != CHAIN_ID) {
      revert(
        string.concat(
          "Chain id should be ",
          vm.toString(CHAIN_ID),
          " (",
          NAME,
          "), is ",
          vm.toString(block.chainid)
        )
      );
    }
  }

  function label(address addr, string memory str) internal {
    vm.label(addr, string.concat(str, "(", NAME, ")"));
  }
}
