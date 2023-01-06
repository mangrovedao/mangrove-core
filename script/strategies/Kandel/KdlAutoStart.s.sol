// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove,
  AbstractKandel,
  MgvStructs
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {KdlPopulate} from "./KdlPopulate.s.sol";
import {KdlSetGeometricDist} from "./KdlSetGeometricDist.s.sol";
import {KdlDeployer, Deployer} from "./KdlDeployer.s.sol";
import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlAutoStart is Deployer, MangroveTest {
  KdlDeployer dep = new KdlDeployer();
  KdlSetGeometricDist dist = new KdlSetGeometricDist();
  KdlPopulate pop = new KdlPopulate();

  function run() public {
    innerRun(
      HeapArgs({
        base: IERC20(envAddressOrName("BASE")),
        quote: IERC20(envAddressOrName("QUOTE")),
        minprice: vm.envUint("MINPRICE"),
        maxprice: vm.envUint("MAXPRICE"),
        popFrom: vm.envUint("FROM"),
        popTo: vm.envUint("TO"),
        base0: vm.envUint("V0"),
        ratio: vm.envUint("RATIO"),
        midprice: vm.envUint("MIDPRICE")
      })
    );
  }

  function getName(IERC20 base, IERC20 quote) public view returns (string memory) {
    return string.concat("Kandel_", base.symbol(), "_", quote.symbol());
  }

  struct HeapArgs {
    IERC20 base;
    IERC20 quote;
    uint minprice;
    uint maxprice;
    uint ratio;
    uint base0;
    uint popFrom;
    uint popTo;
    uint midprice;
  }

  function innerRun(HeapArgs memory args) public {
    uint nslot;
    uint from;
    uint to;
    uint lastBid;
    uint price = args.minprice;

    while (price <= args.maxprice) {
      if (price > args.popFrom && from == 0) {
        from = nslot;
      }
      if (price > args.popTo && to == 0) {
        to = nslot;
      }
      lastBid = (price >= args.midprice) ? lastBid : nslot;
      price = (price * args.ratio) / 100;
      nslot++;
    }

    dep.innerRun(address(args.base), address(args.quote), nslot, 200_000);
    Kandel kdl = Kandel(fork.get(getName(args.base, args.quote)));
    console.log("Kandel deployed:", address(kdl));

    dist.innerRun(kdl, 0, nslot, args.base0, args.minprice, 100, args.ratio);

    (MgvStructs.GlobalPacked global,) = kdl.MGV().config(address(0), address(0));
    pop.innerRun(kdl, from, to, lastBid, global.gasprice() * 5);

    smokeTest(kdl);
  }

  function smokeTest(Kandel kdl) internal {
    IERC20 base_ = kdl.BASE();
    IERC20 quote_ = kdl.QUOTE();
    IMangrove mgv = kdl.MGV();

    vm.prank(broadcaster());
    kdl.checkList(dynamic([IERC20(base_), quote_]));

    address taker = freshAddress("taker");
    deal(address(base_), taker, 0.2 ether);

    vm.startPrank(taker);
    base_.approve(address(mgv), type(uint).max);
    quote_.approve(address(mgv), type(uint).max);

    (, uint takerGave, /*uint bounty*/,) = mgv.marketOrder({
      outbound_tkn: address(quote_),
      inbound_tkn: address(base_),
      takerWants: 0,
      takerGives: 0.2 ether,
      fillWants: false
    });
    vm.stopPrank();

    require(takerGave == 0.2 ether, "market order failed");
    //evaluatePivot will post failing offers on Mangrove so the statement below will not hold
    //require(bounty == 0, 'some offer failed');
  }
}
