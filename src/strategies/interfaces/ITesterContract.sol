// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.0;

import {ILiquidityProvider, IERC20} from "./ILiquidityProvider.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title Interface for testing Forwarder and Direct maker contracts with reserve setters.
interface ITesterContract is ILiquidityProvider {
  function tokenBalance(IERC20 token, address reserveId) external view returns (uint);
}
