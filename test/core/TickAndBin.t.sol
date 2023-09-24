// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_test/lib/MangroveTest.sol";

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
