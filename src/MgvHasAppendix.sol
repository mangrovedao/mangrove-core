// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {HasMgvEvents, MgvStructs, DensityLib, OLKey} from "./MgvLib.sol";
import {MgvAppendix} from "mgv_src/MgvAppendix.sol";
import {MgvCommon} from "mgv_src/MgvCommon.sol";

contract MgvHasAppendix is HasMgvEvents {
  address immutable appendix;

  constructor(address _governance, uint _gasprice, uint gasmax) {
    unchecked {
      emit NewMgv();

      appendix = address(new MgvAppendix());

      /* Initially, governance is open to anyone. */
      /* Set initial gasprice and gasmax. */
      bool success;
      (success,) = appendix.delegatecall(abi.encodeCall(MgvAppendix.setGasprice, (_gasprice)));
      require(success, "mgv/ctor/gasprice");
      (success,) = appendix.delegatecall(abi.encodeCall(MgvAppendix.setGasmax, (gasmax)));
      require(success, "mgv/ctor/gasmax");
      /* Initialize governance to `_governance` after parameter setting. */
      (success,) = appendix.delegatecall(abi.encodeCall(MgvAppendix.setGovernance, (_governance)));
      require(success, "mgv/ctor/governance");
    }
  }

  fallback(bytes calldata callData) external returns (bytes memory) {
    (bool success, bytes memory res) = appendix.delegatecall(callData);
    if (success) {
      return res;
    } else {
      assembly ("memory-safe") {
        revert(add(res, 32), mload(res))
      }
    }
  }
}
