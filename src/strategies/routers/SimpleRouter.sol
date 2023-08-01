// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {SimpleRouterWithoutGasReq} from "./SimpleRouterWithoutGasReq.sol";

///@title `SimpleRouter` instances pull (push) liquidity directly from (to) the an offer owner's account
///@dev Maker contracts using this router must make sure that the reserve approves the router for all asset that will be pulled (outbound tokens)
/// Thus a maker contract using a vault that is not an EOA must make sure this vault has approval capacities.
contract SimpleRouter is SimpleRouterWithoutGasReq(70_000) { // fails for < 70K with Direct strat
}
