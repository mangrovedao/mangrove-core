// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvLib} from "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

///@notice Mangrove instrumented to measure gasused
contract MangroveMeasureGasused is Mangrove {
  // The measured gas usage for the nth invocation of posthook.
  uint[] public totalGasUsed;

  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {}

  function makerPosthook(MgvLib.SingleOrder memory sor, uint gasLeft, bytes32 makerData, bytes32 mgvData)
    internal
    virtual
    override
    returns (uint posthookGas, bool callSuccess, bytes32 posthookData)
  {
    unchecked {
      (posthookGas, callSuccess, posthookData) = super.makerPosthook(sor, gasLeft, makerData, mgvData);
      uint gasreq = sor.offerDetail.gasreq();
      //c.f. super.postExecute: gasLeft = gasreq - gasused; so
      uint gasUsedExecute = gasreq - gasLeft;
      totalGasUsed.push(gasUsedExecute + posthookGas);
    }
  }
}
