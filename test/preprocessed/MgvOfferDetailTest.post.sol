// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "@mgv/lib/Test2.sol";
import "@mgv/src/core/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvOfferDetailTest is Test2 {

  // cleanup arguments with variable number of bits since `pack` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(address maker, uint gasreq, uint kilo_offer_gasbase, uint gasprice) public {
    OfferDetail packed = OfferDetailLib.pack(maker, gasreq, kilo_offer_gasbase, gasprice);
    assertEq(packed.maker(),maker,"bad maker");
    assertEq(packed.gasreq(),cast(gasreq,24),"bad gasreq");
    assertEq(packed.kilo_offer_gasbase(),cast(kilo_offer_gasbase,9),"bad kilo_offer_gasbase");
    assertEq(packed.gasprice(),cast(gasprice,26),"bad gasprice");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_maker(OfferDetail packed,address maker) public {
      OfferDetail original = packed.maker(packed.maker());
      assertEq(original.maker(),packed.maker(), "original: bad maker");

      OfferDetail modified = packed.maker(maker);

      assertEq(modified.maker(),maker,"modified: bad maker");

      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_gasreq(OfferDetail packed,uint gasreq) public {
      OfferDetail original = packed.gasreq(packed.gasreq());
      assertEq(original.gasreq(),packed.gasreq(), "original: bad gasreq");

      OfferDetail modified = packed.gasreq(gasreq);

      assertEq(modified.gasreq(),cast(gasreq,24),"modified: bad gasreq");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_kilo_offer_gasbase(OfferDetail packed,uint kilo_offer_gasbase) public {
      OfferDetail original = packed.kilo_offer_gasbase(packed.kilo_offer_gasbase());
      assertEq(original.kilo_offer_gasbase(),packed.kilo_offer_gasbase(), "original: bad kilo_offer_gasbase");

      OfferDetail modified = packed.kilo_offer_gasbase(kilo_offer_gasbase);

      assertEq(modified.kilo_offer_gasbase(),cast(kilo_offer_gasbase,9),"modified: bad kilo_offer_gasbase");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_gasprice(OfferDetail packed,uint gasprice) public {
      OfferDetail original = packed.gasprice(packed.gasprice());
      assertEq(original.gasprice(),packed.gasprice(), "original: bad gasprice");

      OfferDetail modified = packed.gasprice(gasprice);

      assertEq(modified.gasprice(),cast(gasprice,26),"modified: bad gasprice");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
    }

  function test_unpack(OfferDetail packed) public {
    (address maker, uint gasreq, uint kilo_offer_gasbase, uint gasprice) = packed.unpack();

    assertEq(packed.maker(),maker,"bad maker");
    assertEq(packed.gasreq(),gasreq,"bad gasreq");
    assertEq(packed.kilo_offer_gasbase(),kilo_offer_gasbase,"bad kilo_offer_gasbase");
    assertEq(packed.gasprice(),gasprice,"bad gasprice");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(OfferDetail packed) public {
    OfferDetailUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.maker,packed.maker(),"bad maker");
    assertEq(unpacked.gasreq,packed.gasreq(),"bad gasreq");
    assertEq(unpacked.kilo_offer_gasbase,packed.kilo_offer_gasbase(),"bad kilo_offer_gasbase");
    assertEq(unpacked.gasprice,packed.gasprice(),"bad gasprice");
  }

  function test_inverse_2(OfferDetailUnpacked memory unpacked) public {
    OfferDetail packed = OfferDetailLib.t_of_struct(unpacked);
    OfferDetail packed2;
    packed2 = packed2.maker(unpacked.maker);
    packed2 = packed2.gasreq(unpacked.gasreq);
    packed2 = packed2.kilo_offer_gasbase(unpacked.kilo_offer_gasbase);
    packed2 = packed2.gasprice(unpacked.gasprice);
    assertEq(packed.maker(),packed2.maker(),"bad maker");
    assertEq(packed.gasreq(),packed2.gasreq(),"bad gasreq");
    assertEq(packed.kilo_offer_gasbase(),packed2.kilo_offer_gasbase(),"bad kilo_offer_gasbase");
    assertEq(packed.gasprice(),packed2.gasprice(),"bad gasprice");
  }
}
