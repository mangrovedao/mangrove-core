// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Test2 is Test {
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

  // generate fresh addresses that will be called (and be mocked before being called)
  uint addressIterator = 0;

  function addressToMock() internal returns (address) {
    uint nonce = block.timestamp + (addressIterator++);
    address addr = address(bytes20(keccak256(abi.encode(nonce))));
    // set code to nonzero so solidity-inserted extcodesize checks don't fail
    vm.etch(addr, bytes("not zero"));
    return addr;
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
