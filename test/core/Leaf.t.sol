// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_test/lib/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract LeafTest is MangroveTest {
  function assertStr(Leaf leaf, string memory str) internal {
    assertEq(toString(leaf), str);
  }

  function test_pos_edit() public {
    Leaf leaf = LeafLib.EMPTY;
    assertStr(leaf, "[0,0][0,0][0,0][0,0]");
    leaf = leaf.setPosFirstOrLast(0, 32, false);
    assertStr(leaf, "[32,0][0,0][0,0][0,0]");
    leaf = leaf.setPosFirstOrLast(0, 31, true);
    assertStr(leaf, "[32,31][0,0][0,0][0,0]");
    leaf = leaf.setPosFirstOrLast(3, 12, true);
    assertStr(leaf, "[32,31][0,0][0,0][0,12]");
    leaf = leaf.setPosFirstOrLast(0, 0, true);
    assertStr(leaf, "[32,0][0,0][0,0][0,12]");
    leaf = leaf.setPosFirstOrLast(2, 0, true);
    assertStr(leaf, "[32,0][0,0][0,0][0,12]");
    leaf = leaf.setPosFirstOrLast(2, 1, true);
    assertStr(leaf, "[32,0][0,0][0,1][0,12]");
    leaf = leaf.setPosFirstOrLast(2, 4, false);
    assertStr(leaf, "[32,0][0,0][4,1][0,12]");
    leaf = leaf.setPosFirstOrLast(3, 1208, true);
    assertStr(leaf, "[32,0][0,0][4,1][0,1208]");
    leaf = leaf.setPosFirstOrLast(1, 19992, false);
    assertStr(leaf, "[32,0][19992,0][4,1][0,1208]");
    leaf = leaf.setPosFirstOrLast(1, 711, true);
    assertStr(leaf, "[32,0][19992,711][4,1][0,1208]");
  }

  function test_firstOfferPosition_invalid_leaf_half_1s_lsb() public {
    Leaf leaf = Leaf.wrap((1 << 128) - 1);
    assertEq(leaf.firstOfferPosition(), 2);
  }

  function test_firstOfferPosition_leaf_quarter_1s_lsb() public {
    Leaf leaf;
    leaf = Leaf.wrap((1 << 64) - 1);
    assertEq(leaf.firstOfferPosition(), 3);

    leaf = Leaf.wrap(((1 << 64) - 1) << 64);
    assertEq(leaf.firstOfferPosition(), 2);

    leaf = Leaf.wrap(((1 << 64) - 1) << 128);
    assertEq(leaf.firstOfferPosition(), 1);

    leaf = Leaf.wrap(((1 << 64) - 1) << 192);
    assertEq(leaf.firstOfferPosition(), 0);
  }

  function test_firstOfferPosition() public {
    Leaf leaf = LeafLib.EMPTY;
    leaf = leaf.setBinFirst(Bin.wrap(1), 31);
    leaf = leaf.setBinFirst(Bin.wrap(2), 14);
    leaf = leaf.setBinFirst(Bin.wrap(3), 122);
    assertEq(leaf.firstOfferPosition(), 1, "should be 1");
    leaf = leaf.setBinFirst(Bin.wrap(0), 89);
    assertEq(leaf.firstOfferPosition(), 0, "should be 0");
    leaf = LeafLib.EMPTY;
    leaf = leaf.setBinFirst(Bin.wrap(3), 91);
    assertEq(leaf.firstOfferPosition(), 3, "should be 3");
  }

  int constant BP = 1.0001 * 1e18;

  function test_x_of_pos(uint pos, uint32 firstId, uint32 lastId) public {
    Leaf leaf = LeafLib.EMPTY;
    pos = bound(pos, 0, 3);
    leaf = leaf.setPosFirstOrLast(pos, firstId, false);
    leaf = leaf.setPosFirstOrLast(pos, lastId, true);
    assertEq(leaf.firstOfPos(pos), firstId, "first id");
    assertEq(leaf.lastOfPos(pos), lastId, "last id");
  }

  function test_firstOfferPosition_on_invalid_leaf() public {
    Leaf leaf = LeafLib.EMPTY;
    leaf = leaf.setPosFirstOrLast(0, 1, true);
    leaf = leaf.setPosFirstOrLast(1, 2, false);
    assertEq(leaf.firstOfferPosition(), 0, "first offer position should be 0 (despite leaf being invalid)");
  }

  function test_next_offer_id() public {
    Leaf leaf = LeafLib.EMPTY;
    assertEq(leaf.getNextOfferId(), 0);
    Leaf leaf2 = leaf.setPosFirstOrLast(0, 32, false);
    checkFirstOffer(leaf2, 32);
    leaf2 = leaf.setPosFirstOrLast(0, 12, true);
    checkFirstOffer(leaf2, 0);
    leaf2 = leaf.setPosFirstOrLast(1, 27, false);
    checkFirstOffer(leaf2, 27);
    leaf2 = leaf.setPosFirstOrLast(1, 823, false);
    leaf2 = leaf.setPosFirstOrLast(0, 13, true);
    checkFirstOffer(leaf2, 0);
    leaf = leaf.setPosFirstOrLast(3, 2113, false);
    checkFirstOffer(leaf, 2113);
    leaf = leaf.setPosFirstOrLast(3, 2, false);
    checkFirstOffer(leaf, 2);
    leaf = leaf.setPosFirstOrLast(2, 909, false);
    checkFirstOffer(leaf, 909);
    leaf = leaf.setPosFirstOrLast(2, 0, false);
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

contract TickAndBinTest is MangroveTest {
  function test_posInLeaf_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    assertEq(int(Bin.wrap(bin).posInLeaf()), tn % LEAF_SIZE);
  }

  function test_posInLevel3_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    assertEq(int(Bin.wrap(bin).posInLevel3()), tn / LEAF_SIZE % LEVEL_SIZE);
  }

  function test_posInLevel2_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    assertEq(int(Bin.wrap(bin).posInLevel2()), tn / (LEAF_SIZE * LEVEL_SIZE) % LEVEL_SIZE);
  }

  function test_posInLevel1_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    assertEq(int(Bin.wrap(bin).posInLevel1()), tn / (LEAF_SIZE * (LEVEL_SIZE ** 2)) % LEVEL_SIZE, "wrong posInLevel1");
  }

  // note that tick(p) is max {t | ratio(t) <= p}
  function test_tickFromVolumes() public {
    assertEq(TickLib.tickFromVolumes(1, 1), Tick.wrap(0));
    assertEq(TickLib.tickFromVolumes(2, 1), Tick.wrap(6931));
    assertEq(TickLib.tickFromVolumes(1, 2), Tick.wrap(-6932));
    assertEq(TickLib.tickFromVolumes(1e18, 1), Tick.wrap(414486));
    assertEq(TickLib.tickFromVolumes(type(uint96).max, 1), Tick.wrap(665454));
    assertEq(TickLib.tickFromVolumes(1, type(uint96).max), Tick.wrap(-665455));
    assertEq(TickLib.tickFromVolumes(type(uint72).max, 1), Tick.wrap(499090));
    assertEq(TickLib.tickFromVolumes(1, type(uint72).max), Tick.wrap(-499091));
    assertEq(TickLib.tickFromVolumes(999999, 1000000), Tick.wrap(-1));
    assertEq(TickLib.tickFromVolumes(1000000, 999999), Tick.wrap(0));
    assertEq(TickLib.tickFromVolumes(1000000 * 1e18, 999999 * 1e18), Tick.wrap(0));
  }

  function test_ratioFromTick() public {
    inner_test_ratioFromTick({
      tick: Tick.wrap(2 ** 20 - 1),
      expected_sig: 3441571814221581909035848501253497354125574144,
      expected_exp: 0
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(138162),
      expected_sig: 5444510673556857440102348422228887810808479744,
      expected_exp: 132
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(-1),
      expected_sig: 5708419928830956428590284849313049240594808832,
      expected_exp: 152
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(0),
      expected_sig: 2854495385411919762116571938898990272765493248,
      expected_exp: 151
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(1),
      expected_sig: 2854780834950460954092783596092880171791548416,
      expected_exp: 151
    });
  }

  function inner_test_ratioFromTick(Tick tick, uint expected_sig, uint expected_exp) internal {
    (uint sig, uint exp) = TickLib.ratioFromTick(tick);
    assertEq(expected_sig, sig, "wrong sig");
    assertEq(expected_exp, exp, "wrong exp");
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

  function test_leafIndex_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    int index = tn / LEAF_SIZE - NUM_LEAFS / 2;
    assertEq(Bin.wrap(bin).leafIndex(), index);
  }

  function test_level3Index_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    int index = tn / (LEAF_SIZE * LEVEL_SIZE) - NUM_LEVEL3 / 2;
    assertEq(Bin.wrap(bin).level3Index(), index);
  }

  function test_level2Index_auto(int bin) public {
    bin = bound(bin, MIN_BIN, MAX_BIN);
    int tn = NUM_BINS / 2 + bin; // normalize to positive
    int index = tn / (LEAF_SIZE * (LEVEL_SIZE ** 2)) - NUM_LEVEL2 / 2;
    assertEq(Bin.wrap(bin).level2Index(), index);
  }

  function test_bestBinFromBranch_matches_positions_accessor(
    uint binPosInLeaf,
    uint _level3,
    uint _level2,
    uint _level1,
    uint _root
  ) public {
    binPosInLeaf = bound(binPosInLeaf, 0, 3);
    Field level3 = Field.wrap(bound(_level3, 1, uint(LEVEL_SIZE) - 1));
    Field level2 = Field.wrap(bound(_level2, 1, uint(LEVEL_SIZE) - 1));
    Field level1 = Field.wrap(bound(_level1, 1, uint(LEVEL_SIZE) - 1));
    Field root = Field.wrap(bound(_root, 1, uint(ROOT_SIZE) - 1));
    Local local;
    local = local.binPosInLeaf(binPosInLeaf);
    local = local.level3(level3);
    local = local.level2(level2);
    local = local.level1(level1);
    local = local.root(root);
    Bin bin = BinLib.bestBinFromLocal(local);
    assertEq(bin.posInLeaf(), binPosInLeaf, "wrong pos in leaf");
    assertEq(bin.posInLevel3(), BitLib.ctz64(Field.unwrap(level3)), "wrong pos in level3");
    assertEq(bin.posInLevel2(), BitLib.ctz64(Field.unwrap(level2)), "wrong pos in level2");
    assertEq(bin.posInLevel1(), BitLib.ctz64(Field.unwrap(level1)), "wrong pos in level1");
    assertEq(bin.posInRoot(), BitLib.ctz64(Field.unwrap(root)), "wrong pos in root");
  }

  // HELPER FUNCTIONS
  function assertEq(Bin bin, int ticknum) internal {
    assertEq(Bin.unwrap(bin), ticknum);
  }
}

contract FieldTest is MangroveTest {
  function test_flipBit0(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    Bin bin = Bin.wrap(LEAF_SIZE * int(uint(posInLevel)));
    Field flipped = base.flipBitAtLevel3(bin);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_flipBit1(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    Bin bin = Bin.wrap(LEAF_SIZE * LEVEL_SIZE * int(uint(posInLevel)));
    Field flipped = base.flipBitAtLevel2(bin);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_flipBit2(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(LEVEL_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    Bin bin = Bin.wrap(LEAF_SIZE * LEVEL_SIZE * LEVEL_SIZE * int(uint(posInLevel)));
    Field flipped = base.flipBitAtLevel1(bin);
    assertEq((Field.unwrap(base) ^ Field.unwrap(flipped)), 1 << posInLevel);
  }

  function test_flipBit3(uint _field, uint8 posInLevel) public {
    posInLevel = uint8(bound(posInLevel, 0, uint(ROOT_SIZE - 1)));
    bytes32 field = bytes32(_field);
    Field base = Field.wrap(uint(field));
    int adjustedPos = int(uint(posInLevel)) - ROOT_SIZE / 2;
    Bin bin = Bin.wrap(LEAF_SIZE * (LEVEL_SIZE ** 3) * adjustedPos);
    Field flipped = base.flipBitAtRoot(bin);
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
    assertFirstOnePosition(uint(b), i > MAX_FIELD_SIZE ? MAX_FIELD_SIZE : i);
  }

  function assertFirstOnePosition(uint field, uint pos) internal {
    assertEq(Field.wrap(field).firstOnePosition(), pos);
  }

  function ratio_ratioFromVolumes_not_zero_div() public {
    // should not revert
    (uint man,) = TickLib.ratioFromVolumes(1, type(uint).max);
    assertTrue(man != 0, "mantissa cannot be 0");
  }

  function ratio_ratioFromVolumes_not_zero_div_fuzz(uint inbound, uint outbound) public {
    vm.assume(inbound != 0);
    vm.assume(outbound != 0);
    // should not revert
    (uint man,) = TickLib.ratioFromVolumes(inbound, outbound);
    assertTrue(man != 0, "mantissa cannot be 0");
  }

  /* Field dirty/clean */

  function test_clean_field_idempotent(DirtyField field) public {
    Field cleaned = field.clean();
    assertTrue(cleaned.eq(DirtyField.wrap(Field.unwrap(cleaned)).clean()));
  }

  function test_dirty_field_idempotent(Field field) public {
    // field = Field.wrap(Field.unwrap(field)& NOT_TOPBIT);
    DirtyField dirtied = field.dirty();
    assertTrue(dirtied.eq(Field.wrap(DirtyField.unwrap(dirtied)).dirty()));
  }

  function test_dirty_clean_inverse(uint field) public {
    vm.assume(DirtyField.wrap(field).isDirty());
    DirtyField inv = DirtyField.wrap(field).clean().dirty();
    assertTrue(inv.eq(DirtyField.wrap(field)));
  }

  function test_dirty_invariant_under_clean(uint field) public {
    DirtyField under = DirtyField.wrap(field).clean().dirty();
    assertTrue(under.eq(Field.wrap(field).dirty()));
  }

  function test_clean_dirty_inverse(uint field) public {
    vm.assume(!DirtyField.wrap(field).isDirty());
    Field inv = Field.wrap(field).dirty().clean();
    assertTrue(inv.eq(Field.wrap(field)));
  }

  function test_clean_invariant_under_dirty(uint field) public {
    Field under = Field.wrap(field).dirty().clean();
    assertTrue(under.eq(DirtyField.wrap(field).clean()));
  }

  function test_clean_field_on_0() public {
    uint ufield = Field.unwrap(DirtyField.wrap(0).clean());
    assertEq(ufield, 0);
  }

  function test_clean_field_on_topbit() public {
    uint ufield = Field.unwrap(DirtyField.wrap(TOPBIT).clean());
    assertEq(ufield, 0);
  }

  function test_clean_field_fuzz(uint field) public {
    vm.assume(!DirtyField.wrap(field).isDirty());
    assertEq(Field.unwrap(DirtyField.wrap(field).clean()), field);
  }

  function test_dirty_field_on_0() public {
    uint ufield = DirtyField.unwrap(Field.wrap(0).dirty());
    assertEq(ufield, TOPBIT);
  }

  function test_dirty_field_on_topbit() public {
    uint ufield = DirtyField.unwrap(Field.wrap(TOPBIT).dirty());
    assertEq(ufield, TOPBIT);
  }

  function test_dirty_field_fuzz(uint field) public {
    vm.assume(DirtyField.wrap(field).isDirty());
    assertEq(DirtyField.unwrap(Field.wrap(field).dirty()), field);
  }

  function field_isDirty(DirtyField field) public {
    assertEq(field.isDirty(), DirtyField.unwrap(field) & TOPBIT == TOPBIT);
  }

  // non-optimized divExpUp
  function divExpUp_spec(uint a, uint exp) internal pure returns (uint) {
    if (a == 0) return 0;
    if (exp > 255) return 1;
    uint den = 2 ** exp;
    uint carry = a % den == 0 ? 0 : 1;
    return a / den + carry;
  }

  function test_inboundFromOutboundUp_and_converse(Tick tick, uint amt) public {
    amt = bound(amt, 0, MAX_SAFE_VOLUME);
    tick = Tick.wrap(bound(Tick.unwrap(tick), MIN_TICK, MAX_TICK));

    uint sig;
    uint exp;

    //inboundFromOutboundUp
    (sig, exp) = TickLib.nonNormalizedRatioFromTick(tick);
    assertEq(tick.inboundFromOutboundUp(amt), divExpUp_spec(sig * amt, exp));

    //outboundFromInboundUp
    (sig, exp) = TickLib.nonNormalizedRatioFromTick(Tick.wrap(-Tick.unwrap(tick)));
    assertEq(tick.outboundFromInboundUp(amt), divExpUp_spec(sig * amt, exp));
  }

  function test_divExpUp(uint a, uint exp) public {
    assertEq(TickLib.divExpUp(a, exp), divExpUp_spec(a, exp));
  }
}
