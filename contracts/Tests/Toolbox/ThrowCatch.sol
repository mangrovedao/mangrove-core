// SPDX-License-Identifier: Unlicense

// We can't even encode storage references without the experimental encoder
pragma abicoder v2;

pragma solidity ^0.7.4;
import {Test as T} from "@giry/hardhat-test-solidity/test.sol";
import "hardhat/console.sol";

contract Throw_Test {
  bool called;

  receive() external payable {}

  function throws() external {
    bytes memory s = new bytes(1000); //spend some gas
    s;
    called = true;
  }

  function not_enough_gas_to_call_test() public {
    try this.throws{gas: 100}() {
      T.fail("Function should have failed");
    } catch {
      T.check(!called, "Function should not have been called");
    }
  }

  function enough_gas_to_call_test() public {
    try this.throws{gas: 1000}() {
      T.fail("Function should have failed");
    } catch {
      T.check(!called, "Function should have run out of gas");
    }
  }
}
