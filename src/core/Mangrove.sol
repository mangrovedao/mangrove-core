// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";

import {MgvOfferMaking} from "./MgvOfferMaking.sol";
import {MgvOfferTakingWithPermit} from "./MgvOfferTakingWithPermit.sol";
import {MgvAppendix} from "@mgv/src/core/MgvAppendix.sol";
import {MgvGovernable} from "@mgv/src/core/MgvGovernable.sol";

/* <a id="Mangrove"></a> The `Mangrove` contract inherits both the maker and taker functionality. It also deploys `MgvAppendix` when constructed. */
contract Mangrove is MgvOfferTakingWithPermit, MgvOfferMaking {
  address internal immutable APPENDIX;

  constructor(address governance, uint gasprice, uint gasmax) MgvOfferTakingWithPermit("Mangrove") {
    unchecked {
      emit NewMgv();

      APPENDIX = address(new MgvAppendix());

      /* Set initial gasprice, gasmax, recursion depth and max gasreq for failing offers.  See `MgvAppendix` for why this happens through a delegatecall. */
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
      /* Initially, governance is open to anyone so that Mangrove can set its own default parameters. After that, governance is set to the `governance` constructor argument. */
      (success,) = APPENDIX.delegatecall(abi.encodeCall(MgvGovernable.setGovernance, (governance)));
      require(success, "mgv/ctor/governance");
    }
  }

  /* Fallback to `APPENDIX` if function selector is unknown. */
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
