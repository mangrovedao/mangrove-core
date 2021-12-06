// SPDX-License-Identifier:	AGPL-3.0

// MgvGovernable.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;
pragma abicoder v2;
import {HasMgvEvents, P} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

contract MgvGovernable is MgvRoot {
  // using P.Offer for P.Offer.t;
  // using P.OfferDetail for P.OfferDetail.t;
  using P.Global for P.Global.t;
  using P.Local for P.Local.t;
  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  constructor(
    address _governance,
    uint _gasprice,
    uint gasmax
  ) MgvRoot() { unchecked {
    emit NewMgv();

    /* Initially, governance is open to anyone. */

    /* Initialize vault to governance address, and set initial gasprice and gasmax. */
    setVault(_governance);
    setGasprice(_gasprice);
    setGasmax(gasmax);
    /* Initialize governance to `_governance` after parameter setting. */
    setGovernance(_governance);
  }}

  /* ## `authOnly` check */

  function authOnly() internal view { unchecked {
    require(
      msg.sender == governance ||
        msg.sender == address(this) ||
        governance == address(0),
      "mgv/unauthorized"
    );
  }}

  /* # Set configuration and Mangrove state */

  /* ## Locals */
  /* ### `active` */
  function activate(
    address outbound_tkn,
    address inbound_tkn,
    uint fee,
    uint density,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public { unchecked {
    authOnly();
    locals[outbound_tkn][inbound_tkn] = locals[outbound_tkn][inbound_tkn].active(true);
    emit SetActive(outbound_tkn, inbound_tkn, true);
    setFee(outbound_tkn, inbound_tkn, fee);
    setDensity(outbound_tkn, inbound_tkn, density);
    setGasbase(outbound_tkn, inbound_tkn, overhead_gasbase, offer_gasbase);
  }}

  function deactivate(address outbound_tkn, address inbound_tkn) public {
    authOnly();
    locals[outbound_tkn][inbound_tkn] = locals[outbound_tkn][inbound_tkn].active(false);
    emit SetActive(outbound_tkn, inbound_tkn, false);
  }

  /* ### `fee` */
  function setFee(
    address outbound_tkn,
    address inbound_tkn,
    uint fee
  ) public { unchecked {
    authOnly();
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(fee <= 500, "mgv/config/fee/<=500"); // at most 5%
    locals[outbound_tkn][inbound_tkn] = locals[outbound_tkn][inbound_tkn].fee(fee);
    emit SetFee(outbound_tkn, inbound_tkn, fee);
  }}

  /* ### `density` */
  /* Useless if `global.useOracle != 0` */
  function setDensity(
    address outbound_tkn,
    address inbound_tkn,
    uint density
  ) public { unchecked {
    authOnly();

    require(checkDensity(density), "mgv/config/density/112bits");
    //+clear+
    locals[outbound_tkn][inbound_tkn] = locals[outbound_tkn][inbound_tkn].density(density);
    emit SetDensity(outbound_tkn, inbound_tkn, density);
  }}

  /* ### `gasbase` */
  function setGasbase(
    address outbound_tkn,
    address inbound_tkn,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public { unchecked {
    authOnly();
    /* Checking the size of `*_gasbase` is necessary to prevent a) data loss when `*_gasbase` is copied to an `OfferDetail` struct, and b) overflow when `*_gasbase` is used in calculations. */
    require(
      uint24(overhead_gasbase) == overhead_gasbase,
      "mgv/config/overhead_gasbase/24bits"
    );
    require(
      uint24(offer_gasbase) == offer_gasbase,
      "mgv/config/offer_gasbase/24bits"
    );
    //+clear+
    locals[outbound_tkn][inbound_tkn] = locals[outbound_tkn][inbound_tkn].offer_gasbase(offer_gasbase).overhead_gasbase(overhead_gasbase);
    emit SetGasbase(outbound_tkn, inbound_tkn, overhead_gasbase, offer_gasbase);
  }}

  /* ## Globals */
  /* ### `kill` */
  function kill() public { unchecked {
    authOnly();
    global = global.dead(true);
    emit Kill();
  }}

  /* ### `gasprice` */
  /* Useless if `global.useOracle is != 0` */
  function setGasprice(uint gasprice) public { unchecked {
    authOnly();
    require(checkGasprice(gasprice), "mgv/config/gasprice/16bits");

    //+clear+

    global = global.gasprice(gasprice);
    emit SetGasprice(gasprice);
  }}

  /* ### `gasmax` */
  function setGasmax(uint gasmax) public { unchecked {
    authOnly();
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(gasmax) == gasmax, "mgv/config/gasmax/24bits");
    //+clear+
    global = global.gasmax(gasmax);
    emit SetGasmax(gasmax);
  }}

  /* ### `governance` */
  function setGovernance(address governanceAddress) public { unchecked {
    authOnly();
    governance = governanceAddress;
    emit SetGovernance(governanceAddress);
  }}

  /* ### `vault` */
  function setVault(address vaultAddress) public { unchecked {
    authOnly();
    vault = vaultAddress;
    emit SetVault(vaultAddress);
  }}

  /* ### `monitor` */
  function setMonitor(address monitor) public { unchecked {
    authOnly();
    global = global.monitor(monitor);
    emit SetMonitor(monitor);
  }}

  /* ### `useOracle` */
  function setUseOracle(bool useOracle) public { unchecked {
    authOnly();
    global = global.useOracle(useOracle);
    emit SetUseOracle(useOracle);
  }}

  /* ### `notify` */
  function setNotify(bool notify) public { unchecked {
    authOnly();
    global = global.notify(notify);
    emit SetNotify(notify);
  }}
}
