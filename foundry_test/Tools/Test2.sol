// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Test2 is Test {
  function succeed() internal {
    assertTrue(true);
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
  function not0x(address actual) internal returns (bool) {
    bool success = actual != address(0);
    assertTrue(success, "address should be 0");
    return success;
  }
}
