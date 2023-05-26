// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "mgv_src/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvOfferTest is Test {

  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function test_pack(uint prev, uint next, uint wants, uint gives) public {
    MgvStructs.OfferPacked packed = MgvStructs.Offer.pack(prev, next, wants, gives);
    assertEq(packed.prev(),cast(prev,32),"bad prev");
    assertEq(packed.next(),cast(next,32),"bad next");
    assertEq(packed.wants(),cast(wants,96),"bad wants");
    assertEq(packed.gives(),cast(gives,96),"bad gives");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_prev(MgvStructs.OfferPacked packed,uint prev) public {
      MgvStructs.OfferPacked original = packed.prev(packed.prev());
      assertEq(original.prev(),packed.prev(), "original: bad prev");

      MgvStructs.OfferPacked modified = packed.prev(prev);

      assertEq(modified.prev(),cast(prev,32),"modified: bad prev");

      assertEq(modified.next(),modified.next(),"modified: bad next");
      assertEq(modified.wants(),modified.wants(),"modified: bad wants");
      assertEq(modified.gives(),modified.gives(),"modified: bad gives");
    }
  function test_set_next(MgvStructs.OfferPacked packed,uint next) public {
      MgvStructs.OfferPacked original = packed.next(packed.next());
      assertEq(original.next(),packed.next(), "original: bad next");

      MgvStructs.OfferPacked modified = packed.next(next);

      assertEq(modified.next(),cast(next,32),"modified: bad next");

      assertEq(modified.prev(),modified.prev(),"modified: bad prev");
      assertEq(modified.wants(),modified.wants(),"modified: bad wants");
      assertEq(modified.gives(),modified.gives(),"modified: bad gives");
    }
  function test_set_wants(MgvStructs.OfferPacked packed,uint wants) public {
      MgvStructs.OfferPacked original = packed.wants(packed.wants());
      assertEq(original.wants(),packed.wants(), "original: bad wants");

      MgvStructs.OfferPacked modified = packed.wants(wants);

      assertEq(modified.wants(),cast(wants,96),"modified: bad wants");

      assertEq(modified.prev(),modified.prev(),"modified: bad prev");
      assertEq(modified.next(),modified.next(),"modified: bad next");
      assertEq(modified.gives(),modified.gives(),"modified: bad gives");
    }
  function test_set_gives(MgvStructs.OfferPacked packed,uint gives) public {
      MgvStructs.OfferPacked original = packed.gives(packed.gives());
      assertEq(original.gives(),packed.gives(), "original: bad gives");

      MgvStructs.OfferPacked modified = packed.gives(gives);

      assertEq(modified.gives(),cast(gives,96),"modified: bad gives");

      assertEq(modified.prev(),modified.prev(),"modified: bad prev");
      assertEq(modified.next(),modified.next(),"modified: bad next");
      assertEq(modified.wants(),modified.wants(),"modified: bad wants");
    }

  function test_unpack(MgvStructs.OfferPacked packed) public {
    (uint prev, uint next, uint wants, uint gives) = packed.unpack();

    assertEq(packed.prev(),prev,"bad prev");
    assertEq(packed.next(),next,"bad next");
    assertEq(packed.wants(),wants,"bad wants");
    assertEq(packed.gives(),gives,"bad gives");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(MgvStructs.OfferPacked packed) public {
    MgvStructs.OfferUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.prev,packed.prev(),"bad prev");
    assertEq(unpacked.next,packed.next(),"bad next");
    assertEq(unpacked.wants,packed.wants(),"bad wants");
    assertEq(unpacked.gives,packed.gives(),"bad gives");
  }

  function test_inverse_2(MgvStructs.OfferUnpacked memory unpacked) public {
    MgvStructs.OfferPacked packed = MgvStructs.Offer.t_of_struct(unpacked);
    MgvStructs.OfferPacked packed2;
    packed2 = packed2.prev(unpacked.prev);
    packed2 = packed2.next(unpacked.next);
    packed2 = packed2.wants(unpacked.wants);
    packed2 = packed2.gives(unpacked.gives);
    assertEq(packed.prev(),packed2.prev(),"bad prev");
    assertEq(packed.next(),packed2.next(),"bad next");
    assertEq(packed.wants(),packed2.wants(),"bad wants");
    assertEq(packed.gives(),packed2.gives(),"bad gives");
  }
}
