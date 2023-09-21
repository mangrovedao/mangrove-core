// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {IMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";
import {BinLib, Bin, LEAF_SIZE, LEVEL_SIZE} from "mgv_lib/BinLib.sol";

// A log price with room for bits above and below at all bin levels, except at root which has only 2 bits.
// forgefmt: disable-start
int constant MIDDLE_TICK = 
  /* mid leaf */ LEAF_SIZE / 2 + 
  /* mid level2 */ LEAF_SIZE * (LEVEL_SIZE / 2) +
  /* mid level 1 */ LEAF_SIZE * (LEVEL_SIZE**2)/2  +
  /* mid level 2 */ LEAF_SIZE * (LEVEL_SIZE ** 3)/4;
// forgefmt: disable-end

int constant LEAF_LOWER_TICK = MIDDLE_TICK - 1;
int constant LEAF_HIGHER_TICK = MIDDLE_TICK + 1;
int constant LEVEL2_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE;
int constant LEVEL2_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE;
int constant LEVEL1_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE * LEVEL_SIZE;
int constant LEVEL1_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE * LEVEL_SIZE;
int constant LEVEL0_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE * (LEVEL_SIZE ** 2);
int constant LEVEL0_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE * (LEVEL_SIZE ** 2);
// Not multiplying by full LEVEL_SIZE or ROOT_HIGHER_TICK goes out of tick range
int constant ROOT_LOWER_TICK = MIDDLE_TICK - LEAF_SIZE * (LEVEL_SIZE ** 3) / 2;
int constant ROOT_HIGHER_TICK = MIDDLE_TICK + LEAF_SIZE * (LEVEL_SIZE ** 3) / 2;

abstract contract GasTestBaseStored {
  mapping(int tick => uint offerId) internal tickOfferIds;
  string internal description = "TODO";

  function getStored() internal view virtual returns (IMangrove, TestTaker, OLKey memory, uint);

  function printDescription() public virtual {
    console.log("Description: %s", description);
  }

  function newOfferOnAllTestRatios() public virtual {
    this.newOfferOnAllLowerThanMiddleTestRatios();
    // MIDDLE_TICK is often controlled in tests so leaving it out. mgv.newOfferByTick(_olKey, MIDDLE_TICK, 1 ether, 1_000_000, 0);
    this.newOfferOnAllHigherThanMiddleTestRatios();
  }

  function newOfferOnAllLowerThanMiddleTestRatios() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    tickOfferIds[LEAF_LOWER_TICK] = mgv.newOfferByTick(_olKey, LEAF_LOWER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL2_LOWER_TICK] = mgv.newOfferByTick(_olKey, LEVEL2_LOWER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL1_LOWER_TICK] = mgv.newOfferByTick(_olKey, LEVEL1_LOWER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL0_LOWER_TICK] = mgv.newOfferByTick(_olKey, LEVEL0_LOWER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[ROOT_LOWER_TICK] = mgv.newOfferByTick(_olKey, ROOT_LOWER_TICK, 0.00001 ether, 1_000_000, 0);
  }

  function newOfferOnAllHigherThanMiddleTestRatios() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    tickOfferIds[LEAF_HIGHER_TICK] = mgv.newOfferByTick(_olKey, LEAF_HIGHER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL2_HIGHER_TICK] = mgv.newOfferByTick(_olKey, LEVEL2_HIGHER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL1_HIGHER_TICK] = mgv.newOfferByTick(_olKey, LEVEL1_HIGHER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[LEVEL0_HIGHER_TICK] = mgv.newOfferByTick(_olKey, LEVEL0_HIGHER_TICK, 0.00001 ether, 1_000_000, 0);
    tickOfferIds[ROOT_HIGHER_TICK] = mgv.newOfferByTick(_olKey, ROOT_HIGHER_TICK, 0.00001 ether, 1_000_000, 0);
  }
}

/// In these tests, the testing contract is the market maker.
contract GasTestBase is MangroveTest, IMaker, GasTestBaseStored {
  TestTaker internal _taker;
  uint internal _offerId;

  function setUp() public virtual override {
    super.setUp();
    require(
      olKey.tickSpacing == 1,
      "This contract is only ready for tickSpacing!=1 - depending on tickSpacing the ticks should be changed to test the same boundary conditions"
    );

    _taker = setupTaker(olKey, "Taker");
    deal($(quote), address(_taker), type(uint).max / 3);
    _taker.approveMgv(quote, type(uint).max);

    deal($(base), $(this), type(uint).max / 3);
  }

  /// preload stored vars for better gas estimate
  function getStored() internal view override returns (IMangrove, TestTaker, OLKey memory, uint) {
    return (mgv, _taker, olKey, _offerId);
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual returns (bytes32) {
    return ""; // silence unused function parameter
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    external
    virtual
    override
  {}
}

abstract contract SingleGasTestBase is GasTestBase {
  function test_single_gas() public virtual {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();
    impl(mgv, taker, _olKey, offerId);
    printDescription();
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) internal virtual;
}
