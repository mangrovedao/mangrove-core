// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "mgv_src/MgvLib.sol";

import {MgvOfferMaking} from "./MgvOfferMaking.sol";
import {MgvOfferTakingWithPermit} from "./MgvOfferTakingWithPermit.sol";
import {MgvAppendix} from "mgv_src/MgvAppendix.sol";
import {MgvGovernable} from "mgv_src/MgvGovernable.sol";

/* <a id="Mangrove"></a> The `Mangrove` contract inherits both the maker and taker functionality. It also deploys `MgvAppendix` and delegatescall to the appendix when it receives a call with an unknown selector. That appendix is dedicated to view and governance functions. `MgvAppendix` exists due to bytecode size constraints. */
contract Mangrove is MgvOfferTakingWithPermit, MgvOfferMaking {
  address internal immutable APPENDIX;

  constructor(address governance, uint gasprice, uint gasmax) MgvOfferTakingWithPermit("Mangrove") {
    unchecked {
      emit NewMgv();

      APPENDIX = address(new MgvAppendix());

      /* Initially, governance is open to anyone. */
      /* Set initial gasprice and gasmax. */
      bool success;
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGasprice, (gasprice)));
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
      /* Initialize governance to `governance` after parameter setting. */
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGovernance, (governance)));
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
