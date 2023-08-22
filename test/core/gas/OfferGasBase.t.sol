// // SPDX-License-Identifier:	AGPL-3.0
// pragma solidity ^0.8.10;

// import {MangroveTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "mgv_test/lib/MangroveTest.sol";
// import {IMangrove} from "mgv_src/IMangrove.sol";
// import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
// import {TransferLib} from "mgv_lib/TransferLib.sol";
// import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";
// import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
// import {MIDDLE_TICK} from "./GasTestBase.t.sol";
// import {ActivateSemibook} from "mgv_script/core/ActivateSemibook.s.sol";
// import "mgv_lib/Debug.sol";
// import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
// import {GasTestBaseStored} from "./GasTestBase.t.sol";

// abstract contract OfferGasBaseBaseTest is MangroveTest, GasTestBaseStored {
//   TestTaker taker;
//   PinnedPolygonFork internal fork;

//   function getStored() internal view override returns (AbstractMangrove, TestTaker, address, address, uint) {
//     return (mgv, taker, $(base), $(quote), 0);
//   }

//   function setUp() public virtual override {
//     super.setUp();
//     fork = new PinnedPolygonFork();
//     fork.setUp();
//     options.gasprice = 90;
//     options.gasbase = 200_000;
//     options.defaultFee = 30;
//     mgv = setupMangrove();
//     reader = new MgvReader($(mgv));
//     description = "Offer gasbase measurements";
//   }

//   function setUpTokens(string memory baseToken, string memory quoteToken) public {
//     description = string.concat(description, " - ", baseToken, "/", quoteToken);
//     address baseAddress = fork.get(baseToken);
//     address quoteAddress = fork.get(quoteToken);
//     base = TestToken(baseAddress);
//     quote = TestToken(quoteAddress);
//     setupMarket(olKey);
//     setupMarket(quote, base);

//     taker = setupTaker($(base), $(quote), "Taker");
//     deal($(base), address(taker), 200000 ether);
//     deal($(quote), address(taker), 200000 ether);
//     taker.approveMgv(quote, 200000 ether);
//     taker.approveMgv(base, 200000 ether);

//     address maker = freshAddress("Maker");
//     deal($(base), maker, 200000 ether);
//     deal($(quote), maker, 200000 ether);
//     deal(maker, 1000 ether);
//     vm.prank(maker);
//     mgv.fund{value: 10 ether}();
//     vm.prank(maker);
//     TransferLib.approveToken(base, $(mgv), type(uint).max);
//     vm.prank(maker);
//     TransferLib.approveToken(quote, $(mgv), type(uint).max);
//     vm.prank(maker);
//     mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1, 100000, 0);
//     vm.prank(maker);
//     mgv.newOfferByTick($(quote), $(base), MIDDLE_TICK, 1, 100000, 0);
//   }

//   function test_gasbase_to_empty_book_base_quote() public {
//     AbstractMangrove mgv_ = mgv;
//     vm.prank($(taker));
//     _gas();
//     mgv_.marketOrderByTick($(base), $(quote), MIDDLE_TICK, 1, false);
//     gas_();
//     description = string.concat(description, " - Case: base/quote gasbase for taking single offer to empty book");
//     printDescription();
//   }

//   function test_gasbase_to_empty_book_quote_base() public {
//     AbstractMangrove mgv_ = mgv;
//     vm.prank($(taker));
//     _gas();
//     mgv_.marketOrderByTick($(base), $(quote), MIDDLE_TICK, 1, false);
//     gas_();
//     description = string.concat(description, " - Case: quote/base gasbase for taking single offer to empty book");
//     printDescription();
//   }

//   function test_gasbase_transfers_estimate() public {
//     ActivateSemibook semibook = new ActivateSemibook();
//     uint outbound_gas = semibook.measureTransferGas(base);
//     uint inbound_gas = semibook.measureTransferGas(quote);
//     uint gasbase = 2 * (outbound_gas + inbound_gas);
//     console.log("Gas used: %s", gasbase);
//     description = string.concat(description, " - Case: ActivateSemibook transfers estimate");
//     printDescription();
//   }
// }

// contract OfferGasBaseTest_WETH_DAI is OfferGasBaseBaseTest {
//   function setUp() public override {
//     super.setUp();
//     this.setUpTokens("WETH", "DAI");
//   }
// }
