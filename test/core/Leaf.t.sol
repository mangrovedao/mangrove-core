// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

// import "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Test2.sol";
// import "abdk-libraries-solidity/ABDKMathQuad.sol";
import "mgv_src/MgvLib.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";

// In these tests, the testing contract is the market maker.
contract LeafTest is Test2 {
  function assertStr(Leaf leaf, string memory str) internal {
    assertEq(toString(leaf), str);
  }

  function test_index_edit() public {
    Leaf leaf = LeafLib.EMPTY;
    assertStr(leaf, "[0,0][0,0][0,0][0,0]");
    leaf = leaf.setIndexFirstOrLast(0, 32, false);
    assertStr(leaf, "[32,0][0,0][0,0][0,0]");
    leaf = leaf.setIndexFirstOrLast(0, 31, true);
    assertStr(leaf, "[32,31][0,0][0,0][0,0]");
    leaf = leaf.setIndexFirstOrLast(3, 12, true);
    assertStr(leaf, "[32,31][0,0][0,0][0,12]");
    leaf = leaf.setIndexFirstOrLast(0, 0, true);
    assertStr(leaf, "[32,0][0,0][0,0][0,12]");
    leaf = leaf.setIndexFirstOrLast(2, 0, true);
    assertStr(leaf, "[32,0][0,0][0,0][0,12]");
    leaf = leaf.setIndexFirstOrLast(2, 1, true);
    assertStr(leaf, "[32,0][0,0][0,1][0,12]");
    leaf = leaf.setIndexFirstOrLast(2, 4, false);
    assertStr(leaf, "[32,0][0,0][4,1][0,12]");
    leaf = leaf.setIndexFirstOrLast(3, 1208, true);
    assertStr(leaf, "[32,0][0,0][4,1][0,1208]");
    leaf = leaf.setIndexFirstOrLast(1, 19992, false);
    assertStr(leaf, "[32,0][19992,0][4,1][0,1208]");
    leaf = leaf.setIndexFirstOrLast(1, 711, true);
    assertStr(leaf, "[32,0][19992,711][4,1][0,1208]");
  }

  int constant BP = 1.0001 * 1e18;
  // current max tick with solady fixedpoint lib 1353127

  function test_x_of_index(uint index, uint32 firstId, uint32 lastId) public {
    Leaf leaf = LeafLib.EMPTY;
    index = bound(index, 0, 3);
    leaf = leaf.setIndexFirstOrLast(index, firstId, false);
    leaf = leaf.setIndexFirstOrLast(index, lastId, true);
    assertEq(leaf.firstOfIndex(index), firstId, "first id");
    assertEq(leaf.lastOfIndex(index), lastId, "last id");
  }

  function test_next_offer_id() public {
    Leaf leaf = LeafLib.EMPTY;
    assertEq(leaf.getNextOfferId(), 0);
    Leaf leaf2 = leaf.setIndexFirstOrLast(0, 32, false);
    checkFirstOffer(leaf2, 32);
    leaf2 = leaf.setIndexFirstOrLast(0, 12, true);
    checkFirstOffer(leaf2, 0);
    leaf2 = leaf.setIndexFirstOrLast(1, 27, false);
    checkFirstOffer(leaf2, 27);
    leaf = leaf.setIndexFirstOrLast(0, 13, true);
    leaf2 = leaf.setIndexFirstOrLast(1, 823, false);
    checkFirstOffer(leaf2, 823);
    leaf = leaf.setIndexFirstOrLast(3, 2113, false);
    checkFirstOffer(leaf, 2113);
    leaf = leaf.setIndexFirstOrLast(3, 2, false);
    checkFirstOffer(leaf, 2);
    leaf = leaf.setIndexFirstOrLast(2, 909, false);
    checkFirstOffer(leaf, 909);
    leaf = leaf.setIndexFirstOrLast(2, 0, false);
    checkFirstOffer(leaf, 2);
  }

  // HELPER FUNCTIONS
  function checkFirstOffer(Leaf leaf, uint id) internal {
    assertEq(leaf.getNextOfferId(), id, toString(leaf));
  }
}

contract TickTest is Test {
  function test_posInLeaf_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    assertEq(int(Tick.wrap(tick).posInLeaf()), tn % LEAF_SIZE);
  }

  function test_posInLevel0_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    assertEq(int(Tick.wrap(tick).posInLevel0()), tn / LEAF_SIZE % LEVEL0_SIZE);
  }
  // TODO test_posInLevel1_manual

  function test_posInLevel1_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    assertEq(int(Tick.wrap(tick).posInLevel1()), tn / (LEAF_SIZE * LEVEL0_SIZE) % LEVEL1_SIZE);
  }
  // TODO test_posInLevel2_manual

  function test_posInLevel2_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    assertEq(int(Tick.wrap(tick).posInLevel2()), tn / (LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE) % LEVEL2_SIZE);
  }

  // "price" is the price paid by takers
  // for now tick is rounded towards 0, ie:
  // * gives is stored
  // * if price (wants/gives) < 1, then wants will be higher (ie price will be higher) than real
  // * if price (wants/gives) > 1, then wants will be lower (ie price will be lower) than real
  // * probably should always round price towards -infty
  function test_tickFromVolumes() public {
    assertEq(TickLib.tickFromVolumes(1, 1), 0);
    assertEq(TickLib.tickFromVolumes(2, 1), 6931);
    assertEq(TickLib.tickFromVolumes(1, 2), -6932);
    assertEq(TickLib.tickFromVolumes(1e18, 1), 414486);
    assertEq(TickLib.tickFromVolumes(type(uint96).max, 1), 665454);
    assertEq(TickLib.tickFromVolumes(1, type(uint96).max), -665454);
    assertEq(TickLib.tickFromVolumes(999999, 1000000), -1);
    assertEq(TickLib.tickFromVolumes(1000000, 999999), 0);
    assertEq(TickLib.tickFromVolumes(1000000 * 1e18, 999999 * 1e18), 0);
  }

  function test_priceFromTick() public {
    // 1bp of 1bp as 18 decimals fixed point number
    uint err = 1e18 / 100 / 100 / 100 / 100;
    // tick is ln_bp(1e6)
    // compares to 1.0001**tick*1e18
    assertApproxEqRel(Tick.wrap(138162).priceFromTick_e18(), 999998678087145849760004, err);
    // tick is ln_bp(1)
    // compares to 1.0001**tick*1e18
    assertApproxEqRel(Tick.wrap(0).priceFromTick_e18(), 1.0001 ** 0 * 1e18, err);
    // tick is ln_bp(type(uint96).max)
    // compares to 1.0001**tick*1e18
    assertApproxEqRel(Tick.wrap(665454).priceFromTick_e18(), 79223695601626514454341026560883173411222330007, err);
    // console.log(Tick.wrap(-421417).priceFromTick_e18());
  }

  function showTickApprox(uint wants, uint gives) internal pure {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    uint wants2 = tick.inboundFromOutbound(gives);
    uint gives2 = tick.outboundFromInbound(wants);
    console.log("tick  ", toString(tick));
    console.log("wants ", wants);
    console.log("wants2", wants2);
    console.log("--------------");
    console.log(wants < wants2);
    console.log(wants > wants2);
    console.log(gives < gives2);
    console.log(gives > gives2);
    console.log("===========");
  }

  function tickShifting() public pure {
    showTickApprox(30 ether, 1 ether);
    showTickApprox(30 ether, 30 * 30 ether);
    showTickApprox(1 ether, 1 ether);
  }

  // int constant min_tick_abs = int(2**(TICK_BITS-1));
  function test_leafIndex_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    int index = tn / LEAF_SIZE - NUM_LEAFS / 2;
    assertEq(Tick.wrap(tick).leafIndex(), index);
  }

  function test_level0Index_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    int index = tn / (LEAF_SIZE * LEVEL0_SIZE) - NUM_LEVEL0 / 2;
    assertEq(Tick.wrap(tick).level0Index(), index);
  }

  function test_level1Index_auto(int tick) public {
    tick = bound(tick, MIN_TICK, MAX_TICK);
    int tn = NUM_TICKS / 2 + tick; // normalize to positive
    int index = tn / (LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE) - NUM_LEVEL1 / 2;
    assertEq(Tick.wrap(tick).level1Index(), index);
  }

  // HELPER FUNCTIONS
  function assertEq(Tick tick, int ticknum) internal {
    assertEq(Tick.unwrap(tick), ticknum);
  }
}

contract FieldTest is Test {
  function test_flipBit0(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL0_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    Tick tick = Tick.wrap(LEAF_SIZE * int(uint(posInLevel)));
    Field flipped = base.flipBitAtLevel0(tick);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_flipBit1(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL1_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    Tick tick = Tick.wrap(LEAF_SIZE * LEVEL0_SIZE * int(uint(posInLevel)));
    Field flipped = base.flipBitAtLevel1(tick);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_flipBit2(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL2_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    int adjustedPos = int(uint(posInLevel)) - LEVEL2_SIZE / 2;
    Tick tick = Tick.wrap(LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE * adjustedPos);
    Field flipped = base.flipBitAtLevel2(tick);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_firstOnePosition_manual() public {
    assertFirstOnePosition(1, 0);
    assertFirstOnePosition(1 << 1, 1);
    assertFirstOnePosition(1 << 3, 3);
  }

  function test_firstOnePosition_auto(uint _b) public {
    vm.assume(_b != 0);
    bytes32 b = bytes32(_b);
    uint i;
    for (; i < 256; i++) {
      if (uint(b >> i) % 2 == 1) break;
    }
    assertFirstOnePosition(uint(b), i);
  }

  function assertFirstOnePosition(uint field, uint pos) internal {
    assertEq(Field.wrap(field).firstOnePosition(), pos);
  }
}
