// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib} from "./MgvLib.sol";

import {MgvOfferMaking} from "./MgvOfferMaking.sol";
import {MgvOfferTakingWithPermit} from "./MgvOfferTakingWithPermit.sol";
import {MgvAppendix} from "mgv_src/MgvAppendix.sol";
import {MgvGovernable} from "mgv_src/MgvGovernable.sol";
import {INITIAL_MAX_RECURSION_DEPTH, INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER} from "mgv_lib/Constants.sol";

/* `AbstractMangrove` inherits the two contracts that implement generic Mangrove functionality (`MgvOfferTakingWithPermit` and `MgvOfferMaking`) but does not implement the abstract functions. */
abstract contract AbstractMangrove is MgvOfferTakingWithPermit, MgvOfferMaking {
  address internal immutable APPENDIX;

  constructor(address _governance, uint _gasprice, uint gasmax, string memory contractName)
    MgvOfferTakingWithPermit(contractName)
  {
    unchecked {
      emit NewMgv();

      APPENDIX = address(new MgvAppendix());

      /* Initially, governance is open to anyone. */
      /* Set initial gasprice and gasmax. */
      bool success;
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGasprice, (_gasprice)));
      require(success, "mgv/ctor/gasprice");
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGasmax, (gasmax)));
      require(success, "mgv/ctor/gasmax");
      (success,) =
        APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setMaxRecursionDepth, (INITIAL_MAX_RECURSION_DEPTH)));
      require(success, "mgv/ctor/maxRecursionDepth");
      (success,) = APPENDIX.delegatecall(
        abi.encodeCall(
          MgvGovernable.setMaxGasreqForFailingOffers, (INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER * gasmax)
        )
      );
      require(success, "mgv/ctor/maxGasreqForFailingOffers");
      /* Initialize governance to `_governance` after parameter setting. */
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGovernance, (_governance)));
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
