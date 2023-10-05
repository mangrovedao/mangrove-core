// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/lib/Test2.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/test/lib/MangroveTest.sol";

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
    // The expected values given below are computed by doing:
    // let price = 1.0001^tick
    // let sig = round(price * 2^exp) with exp chosen such that sig uses 128 bits
    // add or remove as necessary to match the error of the `ratioFromTick` function
    inner_test_ratioFromTick({
      tick: Tick.wrap(MAX_TICK),
      expected_sig: MAX_RATIO_MANTISSA,
      expected_exp: uint(MAX_RATIO_EXP)
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(MIN_TICK),
      expected_sig: MIN_RATIO_MANTISSA,
      expected_exp: uint(MIN_RATIO_EXP)
    });

    // The +12 is the error
    inner_test_ratioFromTick({
      tick: Tick.wrap(138162),
      expected_sig: 324518124673179235464474464787774551547 + 12,
      expected_exp: 108
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(-1),
      expected_sig: 340248342086729790484326174814286782777,
      expected_exp: 128
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(0),
      expected_sig: 170141183460469231731687303715884105728,
      expected_exp: 127
    });

    inner_test_ratioFromTick({
      tick: Tick.wrap(1),
      expected_sig: 170158197578815278654860472446255694138,
      expected_exp: 127
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

  function test_normalizeRatio_ko() public {
    vm.expectRevert("mgv/normalizeRatio/mantissaIs0");
    TickLib.normalizeRatio(0, 0);
    vm.expectRevert("mgv/normalizeRatio/lowExp");
    TickLib.normalizeRatio(type(uint).max, 0);
  }

  function test_tickFromNormalizedRatio_ko() public {
    vm.expectRevert("mgv/tickFromRatio/tooLow");
    TickLib.tickFromNormalizedRatio(MIN_RATIO_MANTISSA - 1, uint(MIN_RATIO_EXP));
    vm.expectRevert("mgv/tickFromRatio/tooLow");
    TickLib.tickFromNormalizedRatio(MIN_RATIO_MANTISSA, uint(MIN_RATIO_EXP + 1));
    vm.expectRevert("mgv/tickFromRatio/tooHigh");
    TickLib.tickFromNormalizedRatio(MAX_RATIO_MANTISSA + 1, uint(MAX_RATIO_EXP));
    vm.expectRevert("mgv/tickFromRatio/tooHigh");
    TickLib.tickFromNormalizedRatio(MAX_RATIO_MANTISSA, uint(MAX_RATIO_EXP - 1));
  }

  // check no revert
  function test_tickFromNormalizedRatio_ok() public pure {
    TickLib.tickFromNormalizedRatio(MIN_RATIO_MANTISSA, uint(MIN_RATIO_EXP));
    TickLib.tickFromNormalizedRatio(MAX_RATIO_MANTISSA, uint(MAX_RATIO_EXP));
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
    Bin bin = TickTreeLib.bestBinFromLocal(local);
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
