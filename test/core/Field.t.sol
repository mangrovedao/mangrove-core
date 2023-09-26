// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";
import "mgv_test/lib/MangroveTest.sol";

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
}
