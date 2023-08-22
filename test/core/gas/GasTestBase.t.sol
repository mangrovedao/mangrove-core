// /*
// // SPDX-License-Identifier:	AGPL-3.0

// pragma solidity ^0.8.18;

// import {AbstractMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
// import {MgvLib} from "mgv_src/MgvLib.sol";
// import "mgv_lib/Debug.sol";
// import {TickLib, Tick, LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE} from "mgv_lib/TickLib.sol";

// // A tick with room for bits above and below at all levels, not actually mid of level2.
// int constant MIDDLE_TICK = /* mid leaf*/ LEAF_SIZE / 2 /* mid level0 */ + LEAF_SIZE * (LEVEL0_SIZE / 2) /* mid level 1 */
//   + LEAF_SIZE * LEVEL0_SIZE * (LEVEL1_SIZE / 2);

// int constant LEAF_LOWER_TICK = MIDDLE_TICK - 1;
// int constant LEAF_HIGHER_TICK = MIDDLE_TICK + 1;
// int constant LEVEL0_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE;
// int constant LEVEL0_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE;
// int constant LEVEL1_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE * LEVEL0_SIZE;
// int constant LEVEL1_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE * LEVEL0_SIZE;
// int constant LEVEL2_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE;
// int constant LEVEL2_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE;

// abstract contract GasTestBaseStored is MangroveTest {
//   mapping(int tick => uint offerId) internal tickOfferIds;
//   string internal description = "TODO";

//   function getStored() internal view virtual returns (AbstractMangrove, TestTaker, address, address, uint);

//   function printDescription() public virtual {
//     console.log("Description: %s", description);
//   }

//   function newOfferOnAllTestTicks() public virtual {
//     this.newOfferOnAllLowerThanMiddleTestTicks();
//     // MIDDLE_TICK is often controlled in tests so leaving it out. mgv.newOfferByLogPrice(base, quote, MIDDLE_TICK, 1 ether, 1_000_000, 0);
//     this.newOfferOnAllHigherThanMiddleTestTicks();
//   }

//   function newOfferOnAllLowerThanMiddleTestTicks() public virtual {
//     (AbstractMangrove mgv,, OLKey memory _olKey,) = getStored();
//     tickOfferIds[LEAF_LOWER_TICK] = mgv.newOfferByLogPrice(base, quote, LEAF_LOWER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL0_LOWER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL0_LOWER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL1_LOWER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL1_LOWER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL2_LOWER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL2_LOWER_TICK, 1 ether, 1_000_000, 0);
//   }

//   function newOfferOnAllHigherThanMiddleTestTicks() public virtual {
//     (AbstractMangrove mgv,, OLKey memory _olKey,) = getStored();
//     tickOfferIds[LEAF_HIGHER_TICK] = mgv.newOfferByLogPrice(base, quote, LEAF_HIGHER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL0_HIGHER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL0_HIGHER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL1_HIGHER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL1_HIGHER_TICK, 1 ether, 1_000_000, 0);
//     tickOfferIds[LEVEL2_HIGHER_TICK] = mgv.newOfferByLogPrice(base, quote, LEVEL2_HIGHER_TICK, 1 ether, 1_000_000, 0);
//   }
// }

// /// In these tests, the testing contract is the market maker.
// // FIXME This and all descendant contracts are not ready for tickScale!=1
// contract GasTestBase is MangroveTest, IMaker, GasTestBaseStored {
//   TestTaker internal _taker;
//   uint internal _offerId;

//   function setUp() public virtual override {
//     super.setUp();
//     require(olKey.tickScale == 1, "FIXME: this contract is not ready for tickScale!=1");

//     _taker = setupTaker($(base), $(quote), "Taker");
//     deal($(quote), address(_taker), 200000 ether);
//     _taker.approveMgv(quote, 200000 ether);

//     deal($(base), $(this), 200000 ether);
//   }

//   /// preload stored vars for better gas estimate
//   function getStored() internal view override returns (AbstractMangrove, TestTaker, address, address, uint) {
//     return (mgv, _taker, olKey, _offerId);
//   }

//   function makerExecute(MgvLib.SingleOrder calldata) external virtual returns (bytes32) {
//     return ""; // silence unused function parameter
//   }

//   function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
//     external
//     virtual
//     override
//   {}
// }

// abstract contract SingleGasTestBase is GasTestBase {
//   function test_single_gas() public virtual {
//     (AbstractMangrove mgv, TestTaker taker, address base, address quote, uint offerId) = getStored();
//     impl(mgv, taker, base, quote, offerId);
//     printDescription();
//   }

//   function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint offerId) internal virtual;
// }
