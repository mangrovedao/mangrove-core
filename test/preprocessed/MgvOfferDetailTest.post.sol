// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvOfferDetailTest is Test2 {

  // cleanup arguments with variable number of bits since `pack` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(address maker, uint gasreq, uint offer_gasbase, uint gasprice) public {
    MgvStructs.OfferDetailPacked packed = MgvStructs.OfferDetail.pack(maker, gasreq, offer_gasbase, gasprice);
    assertEq(packed.maker(),maker,"bad maker");
    assertEq(packed.gasreq(),cast(gasreq,24),"bad gasreq");
    assertEq(packed.offer_gasbase(),cast(offer_gasbase,24),"bad offer_gasbase");
    assertEq(packed.gasprice(),cast(gasprice,16),"bad gasprice");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_maker(MgvStructs.OfferDetailPacked packed,address maker) public {
      MgvStructs.OfferDetailPacked original = packed.maker(packed.maker());
      assertEq(original.maker(),packed.maker(), "original: bad maker");

      MgvStructs.OfferDetailPacked modified = packed.maker(maker);

      assertEq(modified.maker(),maker,"modified: bad maker");

      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.offer_gasbase(),packed.offer_gasbase(),"modified: bad offer_gasbase");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_gasreq(MgvStructs.OfferDetailPacked packed,uint gasreq) public {
      MgvStructs.OfferDetailPacked original = packed.gasreq(packed.gasreq());
      assertEq(original.gasreq(),packed.gasreq(), "original: bad gasreq");

      MgvStructs.OfferDetailPacked modified = packed.gasreq(gasreq);

      assertEq(modified.gasreq(),cast(gasreq,24),"modified: bad gasreq");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.offer_gasbase(),packed.offer_gasbase(),"modified: bad offer_gasbase");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_offer_gasbase(MgvStructs.OfferDetailPacked packed,uint offer_gasbase) public {
      MgvStructs.OfferDetailPacked original = packed.offer_gasbase(packed.offer_gasbase());
      assertEq(original.offer_gasbase(),packed.offer_gasbase(), "original: bad offer_gasbase");

      MgvStructs.OfferDetailPacked modified = packed.offer_gasbase(offer_gasbase);

      assertEq(modified.offer_gasbase(),cast(offer_gasbase,24),"modified: bad offer_gasbase");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
    }
  function test_set_gasprice(MgvStructs.OfferDetailPacked packed,uint gasprice) public {
      MgvStructs.OfferDetailPacked original = packed.gasprice(packed.gasprice());
      assertEq(original.gasprice(),packed.gasprice(), "original: bad gasprice");

      MgvStructs.OfferDetailPacked modified = packed.gasprice(gasprice);

      assertEq(modified.gasprice(),cast(gasprice,16),"modified: bad gasprice");

      assertEq(modified.maker(),packed.maker(),"modified: bad maker");
      assertEq(modified.gasreq(),packed.gasreq(),"modified: bad gasreq");
      assertEq(modified.offer_gasbase(),packed.offer_gasbase(),"modified: bad offer_gasbase");
    }

  function test_unpack(MgvStructs.OfferDetailPacked packed) public {
    (address maker, uint gasreq, uint offer_gasbase, uint gasprice) = packed.unpack();

    assertEq(packed.maker(),maker,"bad maker");
    assertEq(packed.gasreq(),gasreq,"bad gasreq");
    assertEq(packed.offer_gasbase(),offer_gasbase,"bad offer_gasbase");
    assertEq(packed.gasprice(),gasprice,"bad gasprice");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(MgvStructs.OfferDetailPacked packed) public {
    MgvStructs.OfferDetailUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.maker,packed.maker(),"bad maker");
    assertEq(unpacked.gasreq,packed.gasreq(),"bad gasreq");
    assertEq(unpacked.offer_gasbase,packed.offer_gasbase(),"bad offer_gasbase");
    assertEq(unpacked.gasprice,packed.gasprice(),"bad gasprice");
  }

  function test_inverse_2(MgvStructs.OfferDetailUnpacked memory unpacked) public {
    MgvStructs.OfferDetailPacked packed = MgvStructs.OfferDetail.t_of_struct(unpacked);
    MgvStructs.OfferDetailPacked packed2;
    packed2 = packed2.maker(unpacked.maker);
    packed2 = packed2.gasreq(unpacked.gasreq);
    packed2 = packed2.offer_gasbase(unpacked.offer_gasbase);
    packed2 = packed2.gasprice(unpacked.gasprice);
    assertEq(packed.maker(),packed2.maker(),"bad maker");
    assertEq(packed.gasreq(),packed2.gasreq(),"bad gasreq");
    assertEq(packed.offer_gasbase(),packed2.offer_gasbase(),"bad offer_gasbase");
    assertEq(packed.gasprice(),packed2.gasprice(),"bad gasprice");
  }
}
