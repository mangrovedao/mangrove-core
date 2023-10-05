// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "@mgv/lib/Test2.sol";
import "@mgv/src/core/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvOfferTest is Test2 {

  // cleanup arguments with variable number of bits since `pack` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(uint prev, uint next, Tick tick, uint gives) public {
    Offer packed = OfferLib.pack(prev, next, tick, gives);
    assertEq(packed.prev(),cast(prev,32),"bad prev");
    assertEq(packed.next(),cast(next,32),"bad next");
    assertEq(Tick.unwrap(packed.tick()),cast(Tick.unwrap(tick),21),"bad tick");
    assertEq(packed.gives(),cast(gives,127),"bad gives");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_prev(Offer packed,uint prev) public {
      Offer original = packed.prev(packed.prev());
      assertEq(original.prev(),packed.prev(), "original: bad prev");

      Offer modified = packed.prev(prev);

      assertEq(modified.prev(),cast(prev,32),"modified: bad prev");

      assertEq(modified.next(),packed.next(),"modified: bad next");
      assertEq(Tick.unwrap(modified.tick()),Tick.unwrap(packed.tick()),"modified: bad tick");
      assertEq(modified.gives(),packed.gives(),"modified: bad gives");
    }
  function test_set_next(Offer packed,uint next) public {
      Offer original = packed.next(packed.next());
      assertEq(original.next(),packed.next(), "original: bad next");

      Offer modified = packed.next(next);

      assertEq(modified.next(),cast(next,32),"modified: bad next");

      assertEq(modified.prev(),packed.prev(),"modified: bad prev");
      assertEq(Tick.unwrap(modified.tick()),Tick.unwrap(packed.tick()),"modified: bad tick");
      assertEq(modified.gives(),packed.gives(),"modified: bad gives");
    }
  function test_set_tick(Offer packed,Tick tick) public {
      Offer original = packed.tick(packed.tick());
      assertEq(Tick.unwrap(original.tick()),Tick.unwrap(packed.tick()), "original: bad tick");

      Offer modified = packed.tick(tick);

      assertEq(Tick.unwrap(modified.tick()),cast(Tick.unwrap(tick),21),"modified: bad tick");

      assertEq(modified.prev(),packed.prev(),"modified: bad prev");
      assertEq(modified.next(),packed.next(),"modified: bad next");
      assertEq(modified.gives(),packed.gives(),"modified: bad gives");
    }
  function test_set_gives(Offer packed,uint gives) public {
      Offer original = packed.gives(packed.gives());
      assertEq(original.gives(),packed.gives(), "original: bad gives");

      Offer modified = packed.gives(gives);

      assertEq(modified.gives(),cast(gives,127),"modified: bad gives");

      assertEq(modified.prev(),packed.prev(),"modified: bad prev");
      assertEq(modified.next(),packed.next(),"modified: bad next");
      assertEq(Tick.unwrap(modified.tick()),Tick.unwrap(packed.tick()),"modified: bad tick");
    }

  function test_unpack(Offer packed) public {
    (uint prev, uint next, Tick tick, uint gives) = packed.unpack();

    assertEq(packed.prev(),prev,"bad prev");
    assertEq(packed.next(),next,"bad next");
    assertEq(Tick.unwrap(packed.tick()),Tick.unwrap(tick),"bad tick");
    assertEq(packed.gives(),gives,"bad gives");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(Offer packed) public {
    OfferUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.prev,packed.prev(),"bad prev");
    assertEq(unpacked.next,packed.next(),"bad next");
    assertEq(Tick.unwrap(unpacked.tick),Tick.unwrap(packed.tick()),"bad tick");
    assertEq(unpacked.gives,packed.gives(),"bad gives");
  }

  function test_inverse_2(OfferUnpacked memory unpacked) public {
    Offer packed = OfferLib.t_of_struct(unpacked);
    Offer packed2;
    packed2 = packed2.prev(unpacked.prev);
    packed2 = packed2.next(unpacked.next);
    packed2 = packed2.tick(unpacked.tick);
    packed2 = packed2.gives(unpacked.gives);
    assertEq(packed.prev(),packed2.prev(),"bad prev");
    assertEq(packed.next(),packed2.next(),"bad next");
    assertEq(Tick.unwrap(packed.tick()),Tick.unwrap(packed2.tick()),"bad tick");
    assertEq(packed.gives(),packed2.gives(),"bad gives");
  }
}
