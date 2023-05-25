// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OfferForwarder, IMangrove, IERC20, AbstractRouter} from "./OfferForwarder.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {ITesterContract} from "mgv_src/strategies/interfaces/ITesterContract.sol";

contract ForwarderTester is OfferForwarder, ITesterContract {
  constructor(IMangrove mgv, address deployer) OfferForwarder(mgv, deployer) {}

  function tokenBalance(IERC20 token, address owner) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_.balanceOfReserve(token, owner);
  }

  function internal_addOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, address owner, uint leftover)
    external
  {
    addOwner(outbound_tkn, inbound_tkn, offerId, owner, leftover);
  }

  function internal__put__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __put__(amount, order);
  }

  function internal__get__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __get__(amount, order);
  }

  function internal__posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    external
    returns (bytes32)
  {
    return __posthookFallback__(order, result);
  }
}
