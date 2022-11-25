// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

/// Replaces EOA in tests (use prank to approve tokens)
/// Allows testing of native token transfer fail

contract TestSender {
  bool acceptNative = true;

  receive() external payable {
    require(acceptNative, "TestSender/refusesNative");
  }

  function refuseNative() external {
    acceptNative = false;
  }
}
