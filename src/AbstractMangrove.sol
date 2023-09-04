// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib} from "./MgvLib.sol";

import {MgvOfferMaking} from "./MgvOfferMaking.sol";
import {MgvOfferTakingWithPermit} from "./MgvOfferTakingWithPermit.sol";
import {MgvAppendix} from "mgv_src/MgvAppendix.sol";

/* `AbstractMangrove` inherits the two contracts that implement generic Mangrove functionality (`MgvOfferTakingWithPermit` and `MgvOfferMaking`) but does not implement the abstract functions. */
abstract contract AbstractMangrove is MgvOfferTakingWithPermit, MgvOfferMaking {
  address immutable APPENDIX;

  constructor(address _governance, uint _gasprice, uint gasmax, string memory contractName)
    MgvOfferTakingWithPermit(contractName)
  {
    unchecked {
      emit NewMgv();

      APPENDIX = address(new MgvAppendix());

      /* Initially, governance is open to anyone. */
      /* Set initial gasprice and gasmax. */
      bool success;
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvAppendix.setGasprice, (_gasprice)));
      require(success, "mgv/ctor/gasprice");
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvAppendix.setGasmax, (gasmax)));
      require(success, "mgv/ctor/gasmax");
      /* Initialize governance to `_governance` after parameter setting. */
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvAppendix.setGovernance, (_governance)));
      require(success, "mgv/ctor/governance");
    }
  }

  fallback(bytes calldata callData) external returns (bytes memory) {
    (bool success, bytes memory res) = APPENDIX.delegatecall(callData);
    if (success) {
      return res;
    } else {
      assembly ("memory-safe") {
        revert(add(res, 32), mload(res))
      }
    }
  }
}
