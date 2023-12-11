// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {IMangrove, TestTaker, MangroveTest, IMaker} from "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";
import {TickTreeLib, Bin, LEAF_SIZE, LEVEL_SIZE} from "@mgv/lib/core/TickTreeLib.sol";

// A bin with room for bits above and below at all bin levels, except at root which has only 2 bits.
// forgefmt: disable-start
int constant IMIDDLE_BIN = 
  /* mid leaf */ LEAF_SIZE / 2 + 
  /* mid level 3 */ LEAF_SIZE * (LEVEL_SIZE / 2) +
  /* mid level 2 */ LEAF_SIZE * (LEVEL_SIZE**2)/2  +
  /* mid level 1 */ LEAF_SIZE * (LEVEL_SIZE ** 3)/4;
// forgefmt: disable-end

Bin constant MIDDLE_BIN = Bin.wrap(IMIDDLE_BIN);

Bin constant LEAF_LOWER_BIN = Bin.wrap(IMIDDLE_BIN - 1);
Bin constant LEAF_HIGHER_BIN = Bin.wrap(IMIDDLE_BIN + 1);
Bin constant LEVEL3_LOWER_BIN = Bin.wrap(IMIDDLE_BIN - LEAF_SIZE);
Bin constant LEVEL3_HIGHER_BIN = Bin.wrap(IMIDDLE_BIN + LEAF_SIZE);
Bin constant LEVEL2_LOWER_BIN = Bin.wrap(IMIDDLE_BIN - LEAF_SIZE * LEVEL_SIZE);
Bin constant LEVEL2_HIGHER_BIN = Bin.wrap(IMIDDLE_BIN + LEAF_SIZE * LEVEL_SIZE);
Bin constant LEVEL1_LOWER_BIN = Bin.wrap(IMIDDLE_BIN - LEAF_SIZE * (LEVEL_SIZE ** 2));
Bin constant LEVEL1_HIGHER_BIN = Bin.wrap(IMIDDLE_BIN + LEAF_SIZE * (LEVEL_SIZE ** 2));
// Not multiplying by full LEVEL_SIZE or ROOT_HIGHER_BIN goes out of tick range
Bin constant ROOT_LOWER_BIN = Bin.wrap(IMIDDLE_BIN - LEAF_SIZE * (LEVEL_SIZE ** 3) / 2);
Bin constant ROOT_HIGHER_BIN = Bin.wrap(IMIDDLE_BIN + LEAF_SIZE * (LEVEL_SIZE ** 3) / 2);

abstract contract GasTestBaseStored {
  mapping(Bin bin => uint offerId) internal binOfferIds;
  string internal description = "TODO";

  function getStored() internal view virtual returns (IMangrove, TestTaker, OLKey memory, uint);

  function printDescription() public virtual {
    printDescription("");
  }

  function printDescription(string memory postfix) public virtual {
    console.log("Description: %s", string.concat(description, postfix));
  }

  function newOfferOnAllTestRatios() public virtual {
    this.newOfferOnAllLowerThanMiddleTestRatios();
    // MIDDLE_BIN is often controlled in tests so leaving it out. mgv.newOfferByTick(_olKey, MIDDLE_BIN, 1 ether, 1_000_000, 0);
    this.newOfferOnAllHigherThanMiddleTestRatios();
  }

  function newOfferOnAllLowerThanMiddleTestRatios() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    binOfferIds[LEAF_LOWER_BIN] = mgv.newOfferByTick(_olKey, _olKey.tick(LEAF_LOWER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL3_LOWER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL3_LOWER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL2_LOWER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL2_LOWER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL1_LOWER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL1_LOWER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[ROOT_LOWER_BIN] = mgv.newOfferByTick(_olKey, _olKey.tick(ROOT_LOWER_BIN), 0.00001 ether, 1_000_000, 0);
  }

  function newOfferOnAllHigherThanMiddleTestRatios() public virtual {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    binOfferIds[LEAF_HIGHER_BIN] = mgv.newOfferByTick(_olKey, _olKey.tick(LEAF_HIGHER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL3_HIGHER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL3_HIGHER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL2_HIGHER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[LEVEL1_HIGHER_BIN] =
      mgv.newOfferByTick(_olKey, _olKey.tick(LEVEL1_HIGHER_BIN), 0.00001 ether, 1_000_000, 0);
    binOfferIds[ROOT_HIGHER_BIN] = mgv.newOfferByTick(_olKey, _olKey.tick(ROOT_HIGHER_BIN), 0.00001 ether, 1_000_000, 0);
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
