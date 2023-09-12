// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Test2.sol";
// import "abdk-libraries-solidity/ABDKMathQuad.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/LogPriceConversionLib.sol";

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

  function test_firstOfferPosition() public {
    Leaf leaf = LeafLib.EMPTY;
    leaf = leaf.setTickFirst(Tick.wrap(1), 31);
    leaf = leaf.setTickFirst(Tick.wrap(2), 14);
    leaf = leaf.setTickFirst(Tick.wrap(3), 122);
    assertEq(leaf.firstOfferPosition(), 1, "should be 1");
    leaf = leaf.setTickFirst(Tick.wrap(0), 89);
    assertEq(leaf.firstOfferPosition(), 0, "should be 0");
    leaf = LeafLib.EMPTY;
    leaf = leaf.setTickFirst(Tick.wrap(3), 91);
    assertEq(leaf.firstOfferPosition(), 3, "should be 3");
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

  /* Leaf dirty/clean */

  function test_clean_leaf_idempotent(DirtyLeaf leaf) public {
    Leaf cleaned = leaf.clean();
    assertTrue(cleaned.eq(DirtyLeaf.wrap(Leaf.unwrap(cleaned)).clean()));
  }

  function test_dirty_leaf_idempotent(Leaf leaf) public {
    DirtyLeaf dirtied = leaf.dirty();
    assertTrue(dirtied.eq(Leaf.wrap(DirtyLeaf.unwrap(dirtied)).dirty()));
  }

  function test_dirty_clean_inverse(DirtyLeaf leaf) public {
    vm.assume(DirtyLeaf.unwrap(leaf) != 0);
    DirtyLeaf inv = leaf.clean().dirty();
    assertTrue(inv.eq(leaf));
  }

  function test_dirty_invariant_under_clean(uint leaf) public {
    DirtyLeaf under = DirtyLeaf.wrap(leaf).clean().dirty();
    assertTrue(under.eq(Leaf.wrap(leaf).dirty()));
  }

  function test_clean_dirty_inverse(Leaf leaf) public {
    vm.assume(Leaf.unwrap(leaf) != 1);
    Leaf inv = leaf.dirty().clean();
    assertTrue(inv.eq(leaf));
  }

  function test_clean_invariant_under_dirty(uint leaf) public {
    Leaf under = Leaf.wrap(leaf).dirty().clean();
    assertTrue(under.eq(DirtyLeaf.wrap(leaf).clean()));
  }

  function test_clean_leaf_on_0() public {
    uint uleaf = Leaf.unwrap(DirtyLeaf.wrap(0).clean());
    assertEq(uleaf, 0);
  }

  function test_clean_leaf_on_1() public {
    uint uleaf = Leaf.unwrap(DirtyLeaf.wrap(1).clean());
    assertEq(uleaf, 0);
  }

  function test_clean_leaf_fuzz(uint leaf) public {
    vm.assume(leaf != 1);
    assertEq(Leaf.unwrap(DirtyLeaf.wrap(leaf).clean()), leaf);
  }

  function test_dirty_leaf_on_0() public {
    uint uleaf = DirtyLeaf.unwrap(Leaf.wrap(0).dirty());
    assertEq(uleaf, 1);
  }

  function test_dirty_leaf_on_1() public {
    uint uleaf = DirtyLeaf.unwrap(Leaf.wrap(1).dirty());
    assertEq(uleaf, 1);
  }

  function test_dirty_leaf_fuzz(uint leaf) public {
    vm.assume(leaf != 0);
    assertEq(DirtyLeaf.unwrap(Leaf.wrap(leaf).dirty()), leaf);
  }

  function leaf_isDirty(DirtyLeaf leaf) public {
    assertEq(leaf.isDirty(), DirtyLeaf.unwrap(leaf) == ONE);
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
    assertEq(
      int(Tick.wrap(tick).posInLevel2()),
      tn / (LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE) % LEVEL2_SIZE,
      "wrong posInLevel2"
    );
  }

  // note that tick(p) is max {t | price(t) <= p}
  function test_logPriceFromVolumes() public {
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1, 1), 0);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(2, 1), 6931);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1, 2), -6932);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1e18, 1), 414486);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(type(uint96).max, 1), 665454);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1, type(uint96).max), -665455);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(type(uint72).max, 1), 499090);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1, type(uint72).max), -499091);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(999999, 1000000), -1);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1000000, 999999), 0);
    assertEq(LogPriceConversionLib.logPriceFromVolumes(1000000 * 1e18, 999999 * 1e18), 0);
  }

  function test_priceFromLogPrice() public {
    inner_test_priceFromLogPrice({
      tick: 2 ** 20 - 1,
      expected_sig: 3441571814221581909035848501253497354125574144,
      expected_exp: 0
    });

    inner_test_priceFromLogPrice({
      tick: 138162,
      expected_sig: 5444510673556857440102348422228887810808479744,
      expected_exp: 132
    });

    //FIXME
    // Do -1,0,1,max
  }

  function inner_test_priceFromLogPrice(int tick, uint expected_sig, uint expected_exp) internal {
    (uint sig, uint exp) = LogPriceConversionLib.priceFromLogPrice(tick);
    assertEq(expected_sig, sig, "wrong sig");
    assertEq(expected_exp, exp, "wrong exp");
  }

  function showLogPriceApprox(uint wants, uint gives) internal pure {
    int logPrice = LogPriceConversionLib.logPriceFromVolumes(wants, gives);
    uint wants2 = LogPriceLib.inboundFromOutbound(logPrice, gives);
    uint gives2 = LogPriceLib.outboundFromInbound(logPrice, wants);
    console.log("logPrice  ", logPriceToString(logPrice));
    console.log("wants ", wants);
    console.log("wants2", wants2);
    console.log("--------------");
    console.log(wants < wants2);
    console.log(wants > wants2);
    console.log(gives < gives2);
    console.log(gives > gives2);
    console.log("===========");
  }

  function logPriceShifting() public pure {
    showLogPriceApprox(30 ether, 1 ether);
    showLogPriceApprox(30 ether, 30 * 30 ether);
    showLogPriceApprox(1 ether, 1 ether);
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

  function test_tickFromBranch_matches_positions_accessor(uint tickPosInLeaf, uint _level0, uint _level1, uint _level2)
    public
  {
    tickPosInLeaf = bound(tickPosInLeaf, 0, 3);
    Field level0 = Field.wrap(bound(_level0, 1, uint(LEVEL0_SIZE) - 1));
    Field level1 = Field.wrap(bound(_level1, 1, uint(LEVEL1_SIZE) - 1));
    Field level2 = Field.wrap(bound(_level2, 1, uint(LEVEL2_SIZE) - 1));
    Tick tick = TickLib.tickFromBranch(tickPosInLeaf, level0, level1, level2);
    assertEq(tick.posInLeaf(), tickPosInLeaf, "wrong pos in leaf");
    assertEq(tick.posInLevel0(), BitLib.ctz(Field.unwrap(level0)), "wrong pos in level0");
    assertEq(tick.posInLevel1(), BitLib.ctz(Field.unwrap(level1)), "wrong pos in level1");
    assertEq(tick.posInLevel2(), BitLib.ctz(Field.unwrap(level2)), "wrong pos in level2");
  }

  // HELPER FUNCTIONS
  function assertEq(Tick tick, int ticknum) internal {
    assertEq(Tick.unwrap(tick), ticknum);
  }
}

contract FieldTest is Test, MangroveTest {
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

  //FIXME move constants-related tests to a separate contract and test them all
  function test_constants_min_max_price() public {
    (uint man, uint exp) = LogPriceConversionLib.priceFromLogPrice(MIN_LOG_PRICE);
    assertEq(man, MIN_PRICE_MANTISSA);
    assertEq(int(exp), MIN_PRICE_EXP);
    (man, exp) = LogPriceConversionLib.priceFromLogPrice(MAX_LOG_PRICE);
    assertEq(man, MAX_PRICE_MANTISSA);
    assertEq(int(exp), MAX_PRICE_EXP);
  }

  function price_priceFromVolumes_not_zero_div() public {
    // should not revert
    (uint man,) = LogPriceConversionLib.priceFromVolumes(1, type(uint).max);
    assertTrue(man != 0, "mantissa cannot be 0");
  }

  function price_priceFromVolumes_not_zero_div_fuzz(uint inbound, uint outbound) public {
    vm.assume(inbound != 0);
    vm.assume(outbound != 0);
    // should not revert
    (uint man,) = LogPriceConversionLib.priceFromVolumes(inbound, outbound);
    assertTrue(man != 0, "mantissa cannot be 0");
  }

  // Make sure no field is so big that the empty marker (top bit) would corrupt data
  // Must be updated manually if new field sizes appear
  function test_field_sizes() public {
    assertLt(LEVEL0_SIZE, 256, "level0 too big");
    assertLt(LEVEL1_SIZE, 256, "level1 too big");
    assertLt(LEVEL2_SIZE, 256, "level2 too big");
  }

  // Since "Only direct number constants and references to such constants are supported by inline assembly", NOT_TOPBIT is not defined in terms of TOPBIT. Here we check that its definition is correct.
  function test_not_topbit_is_negation_of_topbit() public {
    assertEq(TOPBIT, ~NOT_TOPBIT, "TOPBIT != ~NOT_TOPBIT");
  }

  /* Field dirty/clean */

  function test_clean_field_idempotent(Field field) public {
    Field cleaned = field.clean();
    assertTrue(cleaned.eq(cleaned.clean()));
  }

  function test_dirty_field_idempotent(Field field) public {
    Field dirtied = field.dirty();
    assertTrue(dirtied.eq(dirtied.dirty()));
  }

  function test_dirty_clean_inverse(Field field) public {
    vm.assume(field.isDirty());
    Field inv = field.clean().dirty();
    assertTrue(inv.eq(field));
  }

  function test_dirty_invariant_under_clean(Field field) public {
    Field under = field.clean().dirty();
    assertTrue(under.eq(field.dirty()));
  }

  function test_clean_dirty_inverse(Field field) public {
    vm.assume(!field.isDirty());
    Field inv = field.dirty().clean();
    assertTrue(inv.eq(field));
  }

  function test_clean_invariant_under_dirty(Field field) public {
    Field under = field.dirty().clean();
    assertTrue(under.eq(field.clean()));
  }

  function test_clean_field_on_0() public {
    Field field = Field.wrap(0).clean();
    assertEq(field, Field.wrap(0));
  }

  function test_clean_field_on_topbit() public {
    Field field = Field.wrap(TOPBIT).clean();
    assertEq(field, Field.wrap(0));
  }

  function test_clean_field_fuzz(Field field) public {
    vm.assume(!field.isDirty());
    assertEq(field.clean(), field);
  }

  function test_dirty_field_on_0() public {
    Field field = Field.wrap(0).dirty();
    assertEq(field, Field.wrap(TOPBIT));
  }

  function test_dirty_field_on_topbit() public {
    Field field = Field.wrap(TOPBIT).dirty();
    assertEq(field, Field.wrap(TOPBIT));
  }

  function test_dirty_field_fuzz(Field field) public {
    vm.assume(field.isDirty());
    assertEq(field.dirty(), field);
  }

  function field_isDirty(Field field) public {
    assertEq(field.isDirty(), Field.unwrap(field) & TOPBIT == TOPBIT);
  }
}
