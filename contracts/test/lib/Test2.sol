// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Utilities} from "./Utilities.sol";

/* Some ease-of-life additions to forge-std/Test.sol */
/* You mostly want to inherit `MangroveTest` (which inherits `Test2`) rather than inherit `Test2` directly */
contract Test2 is Test, Utilities {
  function succeed() internal {
    assertTrue(true);
  }

  // both mock a call and expect the call to happen
  function expectToMockCall(
    address addr,
    bytes memory req,
    bytes memory res
  ) internal {
    vm.mockCall(addr, req, res);
    vm.expectCall(addr, req);
  }

  uint keyIterator = 1;

  // create addr/key pairs, with/without label
  function freshAccount() internal returns (uint, address payable) {
    uint key = keyIterator++;
    address payable addr = payable(vm.addr(key));
    // set code to nonzero so solidity-inserted extcodesize checks don't fail
    vm.etch(addr, bytes("not zero"));
    return (key, addr);
  }

  function freshAccount(string memory label)
    internal
    returns (uint key, address payable addr)
  {
    (key, addr) = freshAccount();
    vm.label(addr, label);
  }

  function freshKey() internal returns (uint key) {
    (key, ) = freshAccount();
  }

  function freshAddress() internal returns (address payable addr) {
    (, addr) = freshAccount();
  }

  function freshAddress(string memory label)
    internal
    returns (address payable addr)
  {
    (, addr) = freshAccount(label);
  }

  /* expect exact log from address */
  function expectFrom(address addr) internal {
    vm.expectEmit(true, true, true, true, addr);
  }

  /* expect a revert reason */
  function revertEq(string memory actual_reason, string memory expected_reason)
    internal
    returns (bool)
  {
    assertEq(actual_reason, expected_reason, "wrong revert reason");
    return true;
  }

  /* assert address is not 0 */
  function not0x(address a) internal returns (bool) {
    if (a == address(0)) {
      emit log("Error: address should not be 0");
      emit log_named_address("Address", a);
      fail();
    }
    return (a != address(0));
  }

  /* inline gas measures */
  uint private checkpointGasLeft = 1; // Start the slot non0.
  string checkpointLabel;

  /* start measuring gas */
  function _gas() internal virtual {
    // checkpointLabel = label;

    checkpointGasLeft = gasleft();
  }

  /* stop measuring gas and report */
  function gas_() internal virtual {
    uint checkpointGasLeft2 = gasleft();

    // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
    uint gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

    emit log_named_uint("Gas used", gasDelta);
  }

  /* Logging is put here since solidity libraries cannot be extended. */

  function logary(uint[] memory uints) public view {
    string memory s = "";
    for (uint i = 0; i < uints.length; i++) {
      s = string.concat(s, uint2str(uints[i]));
      if (i < uints.length - 1) {
        s = string.concat(s, ", ");
      }
    }
    console2.log(s);
  }

  function logary(int[] memory ints) public view {
    string memory s = "";
    for (uint i = 0; i < ints.length; i++) {
      s = string.concat(s, uint2str(uint(ints[i])));
      if (i < ints.length - 1) {
        s = string.concat(s, ", ");
      }
    }
    console2.log(s);
  }
}
