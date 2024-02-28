// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {Mangrove} from "../../../core/Mangrove.sol";
import {IBlast} from "../interfaces/IBlast.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";

/// @title BlastMangrove
/// @notice Mangrove extension that adds support for Blast yield and points.
/// @dev ETH yield MUST NOT use automatic mode as governance has no way to extract the yield.
///   This is a security measure, as governance would otherwise be able to steal users'
///   provisions which are stored on Mangrove.
/// @dev As for ETH yield, gas fees MUST NOT be stored on the contract.
//    Automatic claiming of gas fees is not currently supported, so not an issue in practice.
/// @dev WETH and USDB can safely use automatic mode as fees are already stored on the contract
///   and extractable by governance.
contract BlastMangrove is Mangrove {
  constructor(
    address governance,
    uint gasprice,
    uint gasmax,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) Mangrove(governance, gasprice, gasmax) {
    // Ensure yield and gas fees are claimable by `blastGovernor`
    // NB: ETH yield MUST NOT use automatic mode as governance has no way to extract the yield.
    blastContract.configureClaimableYield();

    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);

    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }
}
