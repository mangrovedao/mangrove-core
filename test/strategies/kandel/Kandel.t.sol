// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console2} from "forge-std/Test.sol";

contract NoRouterKandelTest is CoreKandelTest {
  function __deployKandel__(address deployer, address reserveId) internal override returns (GeometricKandel kdl_) {
    uint GASREQ = 128_000; // can be 77_000 when all offers are initialized.

    vm.expectEmit(true, true, true, true);
    emit Mgv(IMangrove($(mgv)));
    vm.expectEmit(true, true, true, true);
    emit Pair(base, quote);
    vm.expectEmit(true, true, true, true);
    emit SetGasprice(bufferedGasprice);
    vm.expectEmit(true, true, true, true);
    emit SetGasreq(GASREQ);
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      reserveId: reserveId
    });
  }
}
