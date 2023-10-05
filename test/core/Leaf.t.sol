// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/lib/Test2.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/test/lib/MangroveTest.sol";
import "@mgv/lib/Debug.sol";

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

  function test_bestNonEmptyBinPos_invalid_leaf_half_1s_lsb() public {
    Leaf leaf = Leaf.wrap((1 << 128) - 1);
    assertEq(leaf.bestNonEmptyBinPos(), 2);
  }

  function test_bestNonEmptyBinPos_leaf_quarter_1s_lsb() public {
    Leaf leaf;
    leaf = Leaf.wrap((1 << 64) - 1);
    assertEq(leaf.bestNonEmptyBinPos(), 3);

    leaf = Leaf.wrap(((1 << 64) - 1) << 64);
    assertEq(leaf.bestNonEmptyBinPos(), 2);

    leaf = Leaf.wrap(((1 << 64) - 1) << 128);
    assertEq(leaf.bestNonEmptyBinPos(), 1);

    leaf = Leaf.wrap(((1 << 64) - 1) << 192);
    assertEq(leaf.bestNonEmptyBinPos(), 0);
  }

  function test_bestNonEmptyBinPos() public {
    Leaf leaf = LeafLib.EMPTY;
    leaf = leaf.setBinFirst(Bin.wrap(1), 31);
    leaf = leaf.setBinFirst(Bin.wrap(2), 14);
    leaf = leaf.setBinFirst(Bin.wrap(3), 122);
    assertEq(leaf.bestNonEmptyBinPos(), 1, "should be 1");
    leaf = leaf.setBinFirst(Bin.wrap(0), 89);
    assertEq(leaf.bestNonEmptyBinPos(), 0, "should be 0");
    leaf = LeafLib.EMPTY;
    leaf = leaf.setBinFirst(Bin.wrap(3), 91);
    assertEq(leaf.bestNonEmptyBinPos(), 3, "should be 3");
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

  function test_bestNonEmptyBinPos_on_invalid_leaf() public {
    Leaf leaf = LeafLib.EMPTY;
    leaf = leaf.setPosFirstOrLast(0, 1, true);
    leaf = leaf.setPosFirstOrLast(1, 2, false);
    assertEq(leaf.bestNonEmptyBinPos(), 0, "first offer position should be 0 (despite leaf being invalid)");
  }

  function test_next_offer_id() public {
    Leaf leaf = LeafLib.EMPTY;
    assertEq(leaf.bestOfferId(), 0);
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
    assertEq(leaf.bestOfferId(), id, toString(leaf));
  }
}
