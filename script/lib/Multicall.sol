// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

pragma experimental ABIEncoderV2;

/// @title Multicall - Aggregate results from multiple read-only function calls
/// @author modified by Mangrove DAO
/// @author Michael Elliot <mike@makerdao.com>
/// @author Joshua Levine <joshua@makerdao.com>
/// @author Nick Johnson <arachnid@notdot.net>

contract Multicall {
  struct Call {
    address target;
    bytes callData;
  }

  function aggregate(Call[] memory calls) public returns (bool[] memory successes, bytes[] memory datas) {
    successes = new bool[](calls.length);
    datas = new bytes[](calls.length);
    unchecked {
      for (uint i = 0; i < calls.length; i++) {
        (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
        successes[i] = success;
        datas[i] = ret;
      }
    }
  }
}
