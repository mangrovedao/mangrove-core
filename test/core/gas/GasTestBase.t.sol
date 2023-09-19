// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {IMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";
import {TickLib, Tick, LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE} from "mgv_lib/TickLib.sol";

// A log price with room for bits above and below at all tick levels, except at level3 which has only 2 bits.
// forgefmt: disable-start
int constant MIDDLE_LOG_PRICE = 
  /* mid leaf */ LEAF_SIZE / 2 + 
  /* mid level0 */ LEAF_SIZE * (LEVEL0_SIZE / 2) +
  /* mid level 1 */ LEAF_SIZE * LEVEL0_SIZE * (LEVEL1_SIZE / 2) +
  /* mid level 2 */ LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE + (LEVEL2_SIZE / 2);
// forgefmt: disable-end

int constant LEAF_LOWER_LOG_PRICE = MIDDLE_LOG_PRICE - 1;
int constant LEAF_HIGHER_LOG_PRICE = MIDDLE_LOG_PRICE + 1;
int constant LEVEL0_LOWER_LOG_PRICE = MIDDLE_LOG_PRICE - LEAF_SIZE;
int constant LEVEL0_HIGHER_LOG_PRICE = MIDDLE_LOG_PRICE + LEAF_SIZE;
int constant LEVEL1_LOWER_LOG_PRICE = MIDDLE_LOG_PRICE - LEAF_SIZE * LEVEL0_SIZE;
int constant LEVEL1_HIGHER_LOG_PRICE = MIDDLE_LOG_PRICE + LEAF_SIZE * LEVEL0_SIZE;
int constant LEVEL2_LOWER_LOG_PRICE = MIDDLE_LOG_PRICE - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE;
int constant LEVEL2_HIGHER_LOG_PRICE = MIDDLE_LOG_PRICE + LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE;
// Not multiplying by full LEVEL2_SIZE or LEVEL3_HIGHER_LOG_PRICE goes out of logPrice range
int constant LEVEL3_LOWER_LOG_PRICE = MIDDLE_LOG_PRICE - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE * LEVEL2_SIZE / 2;
int constant LEVEL3_HIGHER_LOG_PRICE = MIDDLE_LOG_PRICE + LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE * LEVEL2_SIZE / 2;

abstract contract GasTestBaseStored {
  mapping(int logPrice => uint offerId) internal logPriceOfferIds;
  string internal description = "TODO";

  function getStored() internal view virtual returns (IMangrove, TestTaker, OLKey memory, uint);

  function printDescription() public virtual {
    console.log("Description: %s", description);
  }

  function newOfferOnAllTestPrices() public virtual {
    this.newOfferOnAllLowerThanMiddleTestPrices();
    // MIDDLE_LOG_PRICE is often controlled in tests so leaving it out. mgv.newOfferByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1 ether, 1_000_000, 0);
    this.newOfferOnAllHigherThanMiddleTestPrices();
  }

  function newOfferOnAllLowerThanMiddleTestPrices() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    logPriceOfferIds[LEAF_LOWER_LOG_PRICE] = mgv.newOfferByLogPrice(_olKey, LEAF_LOWER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL0_LOWER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL0_LOWER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL1_LOWER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL1_LOWER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL2_LOWER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL2_LOWER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL3_LOWER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL3_LOWER_LOG_PRICE, 1 ether, 1_000_000, 0);
  }

  function newOfferOnAllHigherThanMiddleTestPrices() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    logPriceOfferIds[LEAF_HIGHER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEAF_HIGHER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL0_HIGHER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL0_HIGHER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL1_HIGHER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL1_HIGHER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL2_HIGHER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL2_HIGHER_LOG_PRICE, 1 ether, 1_000_000, 0);
    logPriceOfferIds[LEVEL3_HIGHER_LOG_PRICE] =
      mgv.newOfferByLogPrice(_olKey, LEVEL3_HIGHER_LOG_PRICE, 1 ether, 1_000_000, 0);
  }
}

/// In these tests, the testing contract is the market maker.
contract GasTestBase is MangroveTest, IMaker, GasTestBaseStored {
  TestTaker internal _taker;
  uint internal _offerId;

  function setUp() public virtual override {
    super.setUp();
    require(
      olKey.tickScale == 1,
      "This contract is only ready for tickScale!=1 - depending on tickScale the logPrices should be changed to test the same boundary conditions"
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
