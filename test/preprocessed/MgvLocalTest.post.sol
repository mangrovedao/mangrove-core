// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvLocalTest is Test2 {

  // cleanup arguments with variable number of bits since `pack` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(bool active, uint fee, Density density, uint tickPosInLeaf, Field level0, Field level1, Field level2, Field root, uint kilo_offer_gasbase, bool lock, uint last) public {
    MgvStructs.LocalPacked packed = MgvStructs.Local.pack(active, fee, density, tickPosInLeaf, level0, level1, level2, root, kilo_offer_gasbase, lock, last);
    assertEq(packed.active(),active,"bad active");
    assertEq(packed.fee(),cast(fee,8),"bad fee");
    assertEq(Density.unwrap(packed.density()),cast(Density.unwrap(density),9),"bad density");
    assertEq(packed.tickPosInLeaf(),cast(tickPosInLeaf,2),"bad tickPosInLeaf");
    assertEq(Field.unwrap(packed.level0()),cast(Field.unwrap(level0),64),"bad level0");
    assertEq(Field.unwrap(packed.level1()),cast(Field.unwrap(level1),64),"bad level1");
    assertEq(Field.unwrap(packed.level2()),cast(Field.unwrap(level2),64),"bad level2");
    assertEq(Field.unwrap(packed.root()),cast(Field.unwrap(root),2),"bad root");
    assertEq(packed.kilo_offer_gasbase(),cast(kilo_offer_gasbase,9),"bad kilo_offer_gasbase");
    assertEq(packed.lock(),lock,"bad lock");
    assertEq(packed.last(),cast(last,32),"bad last");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_active(MgvStructs.LocalPacked packed,bool active) public {
      MgvStructs.LocalPacked original = packed.active(packed.active());
      assertEq(original.active(),packed.active(), "original: bad active");

      MgvStructs.LocalPacked modified = packed.active(active);

      assertEq(modified.active(),active,"modified: bad active");

      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_fee(MgvStructs.LocalPacked packed,uint fee) public {
      MgvStructs.LocalPacked original = packed.fee(packed.fee());
      assertEq(original.fee(),packed.fee(), "original: bad fee");

      MgvStructs.LocalPacked modified = packed.fee(fee);

      assertEq(modified.fee(),cast(fee,8),"modified: bad fee");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_density(MgvStructs.LocalPacked packed,Density density) public {
      MgvStructs.LocalPacked original = packed.density(packed.density());
      assertEq(Density.unwrap(original.density()),Density.unwrap(packed.density()), "original: bad density");

      MgvStructs.LocalPacked modified = packed.density(density);

      assertEq(Density.unwrap(modified.density()),cast(Density.unwrap(density),9),"modified: bad density");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_tickPosInLeaf(MgvStructs.LocalPacked packed,uint tickPosInLeaf) public {
      MgvStructs.LocalPacked original = packed.tickPosInLeaf(packed.tickPosInLeaf());
      assertEq(original.tickPosInLeaf(),packed.tickPosInLeaf(), "original: bad tickPosInLeaf");

      MgvStructs.LocalPacked modified = packed.tickPosInLeaf(tickPosInLeaf);

      assertEq(modified.tickPosInLeaf(),cast(tickPosInLeaf,2),"modified: bad tickPosInLeaf");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_level0(MgvStructs.LocalPacked packed,Field level0) public {
      MgvStructs.LocalPacked original = packed.level0(packed.level0());
      assertEq(Field.unwrap(original.level0()),Field.unwrap(packed.level0()), "original: bad level0");

      MgvStructs.LocalPacked modified = packed.level0(level0);

      assertEq(Field.unwrap(modified.level0()),cast(Field.unwrap(level0),64),"modified: bad level0");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_level1(MgvStructs.LocalPacked packed,Field level1) public {
      MgvStructs.LocalPacked original = packed.level1(packed.level1());
      assertEq(Field.unwrap(original.level1()),Field.unwrap(packed.level1()), "original: bad level1");

      MgvStructs.LocalPacked modified = packed.level1(level1);

      assertEq(Field.unwrap(modified.level1()),cast(Field.unwrap(level1),64),"modified: bad level1");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_level2(MgvStructs.LocalPacked packed,Field level2) public {
      MgvStructs.LocalPacked original = packed.level2(packed.level2());
      assertEq(Field.unwrap(original.level2()),Field.unwrap(packed.level2()), "original: bad level2");

      MgvStructs.LocalPacked modified = packed.level2(level2);

      assertEq(Field.unwrap(modified.level2()),cast(Field.unwrap(level2),64),"modified: bad level2");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_root(MgvStructs.LocalPacked packed,Field root) public {
      MgvStructs.LocalPacked original = packed.root(packed.root());
      assertEq(Field.unwrap(original.root()),Field.unwrap(packed.root()), "original: bad root");

      MgvStructs.LocalPacked modified = packed.root(root);

      assertEq(Field.unwrap(modified.root()),cast(Field.unwrap(root),2),"modified: bad root");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_kilo_offer_gasbase(MgvStructs.LocalPacked packed,uint kilo_offer_gasbase) public {
      MgvStructs.LocalPacked original = packed.kilo_offer_gasbase(packed.kilo_offer_gasbase());
      assertEq(original.kilo_offer_gasbase(),packed.kilo_offer_gasbase(), "original: bad kilo_offer_gasbase");

      MgvStructs.LocalPacked modified = packed.kilo_offer_gasbase(kilo_offer_gasbase);

      assertEq(modified.kilo_offer_gasbase(),cast(kilo_offer_gasbase,9),"modified: bad kilo_offer_gasbase");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_lock(MgvStructs.LocalPacked packed,bool lock) public {
      MgvStructs.LocalPacked original = packed.lock(packed.lock());
      assertEq(original.lock(),packed.lock(), "original: bad lock");

      MgvStructs.LocalPacked modified = packed.lock(lock);

      assertEq(modified.lock(),lock,"modified: bad lock");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.last(),packed.last(),"modified: bad last");
    }
  function test_set_last(MgvStructs.LocalPacked packed,uint last) public {
      MgvStructs.LocalPacked original = packed.last(packed.last());
      assertEq(original.last(),packed.last(), "original: bad last");

      MgvStructs.LocalPacked modified = packed.last(last);

      assertEq(modified.last(),cast(last,32),"modified: bad last");

      assertEq(modified.active(),packed.active(),"modified: bad active");
      assertEq(modified.fee(),packed.fee(),"modified: bad fee");
      assertEq(Density.unwrap(modified.density()),Density.unwrap(packed.density()),"modified: bad density");
      assertEq(modified.tickPosInLeaf(),packed.tickPosInLeaf(),"modified: bad tickPosInLeaf");
      assertEq(Field.unwrap(modified.level0()),Field.unwrap(packed.level0()),"modified: bad level0");
      assertEq(Field.unwrap(modified.level1()),Field.unwrap(packed.level1()),"modified: bad level1");
      assertEq(Field.unwrap(modified.level2()),Field.unwrap(packed.level2()),"modified: bad level2");
      assertEq(Field.unwrap(modified.root()),Field.unwrap(packed.root()),"modified: bad root");
      assertEq(modified.kilo_offer_gasbase(),packed.kilo_offer_gasbase(),"modified: bad kilo_offer_gasbase");
      assertEq(modified.lock(),packed.lock(),"modified: bad lock");
    }

  function test_unpack(MgvStructs.LocalPacked packed) public {
    (bool active, uint fee, Density density, uint tickPosInLeaf, Field level0, Field level1, Field level2, Field root, uint kilo_offer_gasbase, bool lock, uint last) = packed.unpack();

    assertEq(packed.active(),active,"bad active");
    assertEq(packed.fee(),fee,"bad fee");
    assertEq(Density.unwrap(packed.density()),Density.unwrap(density),"bad density");
    assertEq(packed.tickPosInLeaf(),tickPosInLeaf,"bad tickPosInLeaf");
    assertEq(Field.unwrap(packed.level0()),Field.unwrap(level0),"bad level0");
    assertEq(Field.unwrap(packed.level1()),Field.unwrap(level1),"bad level1");
    assertEq(Field.unwrap(packed.level2()),Field.unwrap(level2),"bad level2");
    assertEq(Field.unwrap(packed.root()),Field.unwrap(root),"bad root");
    assertEq(packed.kilo_offer_gasbase(),kilo_offer_gasbase,"bad kilo_offer_gasbase");
    assertEq(packed.lock(),lock,"bad lock");
    assertEq(packed.last(),last,"bad last");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(MgvStructs.LocalPacked packed) public {
    MgvStructs.LocalUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.active,packed.active(),"bad active");
    assertEq(unpacked.fee,packed.fee(),"bad fee");
    assertEq(Density.unwrap(unpacked.density),Density.unwrap(packed.density()),"bad density");
    assertEq(unpacked.tickPosInLeaf,packed.tickPosInLeaf(),"bad tickPosInLeaf");
    assertEq(Field.unwrap(unpacked.level0),Field.unwrap(packed.level0()),"bad level0");
    assertEq(Field.unwrap(unpacked.level1),Field.unwrap(packed.level1()),"bad level1");
    assertEq(Field.unwrap(unpacked.level2),Field.unwrap(packed.level2()),"bad level2");
    assertEq(Field.unwrap(unpacked.root),Field.unwrap(packed.root()),"bad root");
    assertEq(unpacked.kilo_offer_gasbase,packed.kilo_offer_gasbase(),"bad kilo_offer_gasbase");
    assertEq(unpacked.lock,packed.lock(),"bad lock");
    assertEq(unpacked.last,packed.last(),"bad last");
  }

  function test_inverse_2(MgvStructs.LocalUnpacked memory unpacked) public {
    MgvStructs.LocalPacked packed = MgvStructs.Local.t_of_struct(unpacked);
    MgvStructs.LocalPacked packed2;
    packed2 = packed2.active(unpacked.active);
    packed2 = packed2.fee(unpacked.fee);
    packed2 = packed2.density(unpacked.density);
    packed2 = packed2.tickPosInLeaf(unpacked.tickPosInLeaf);
    packed2 = packed2.level0(unpacked.level0);
    packed2 = packed2.level1(unpacked.level1);
    packed2 = packed2.level2(unpacked.level2);
    packed2 = packed2.root(unpacked.root);
    packed2 = packed2.kilo_offer_gasbase(unpacked.kilo_offer_gasbase);
    packed2 = packed2.lock(unpacked.lock);
    packed2 = packed2.last(unpacked.last);
    assertEq(packed.active(),packed2.active(),"bad active");
    assertEq(packed.fee(),packed2.fee(),"bad fee");
    assertEq(Density.unwrap(packed.density()),Density.unwrap(packed2.density()),"bad density");
    assertEq(packed.tickPosInLeaf(),packed2.tickPosInLeaf(),"bad tickPosInLeaf");
    assertEq(Field.unwrap(packed.level0()),Field.unwrap(packed2.level0()),"bad level0");
    assertEq(Field.unwrap(packed.level1()),Field.unwrap(packed2.level1()),"bad level1");
    assertEq(Field.unwrap(packed.level2()),Field.unwrap(packed2.level2()),"bad level2");
    assertEq(Field.unwrap(packed.root()),Field.unwrap(packed2.root()),"bad root");
    assertEq(packed.kilo_offer_gasbase(),packed2.kilo_offer_gasbase(),"bad kilo_offer_gasbase");
    assertEq(packed.lock(),packed2.lock(),"bad lock");
    assertEq(packed.last(),packed2.last(),"bad last");
  }
}
