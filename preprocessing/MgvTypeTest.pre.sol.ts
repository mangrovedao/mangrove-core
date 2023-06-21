import { format, tabulate } from "./lib/format";

export const template = ({ preamble, struct_utilities, struct: s }) => {
  return format`// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "mgv_lib/Test2.sol";
import "mgv_src/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract Mgv${s.Name}Test is Test2 {

  // cleanup arguments with variable number of bits since \`pack\` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(${s.fields.map(f => `${f.type} ${f.name}`).join(", ")}) public {
    MgvStructs.${s.Packed} packed = MgvStructs.${s.Name}.pack(${s.fields.map(f => `${f.name}`).join(", ")});
    ${s.fields.map(f => {
      if (f.rawType === "uint" || f.rawType === "int" ) {
        return `assertEq(${f.unwrapped(`packed.${f.name}()`)},cast(${f.unwrapped(f.name)},${f.bits}),"bad ${f.name}");`
      } else {
        return `assertEq(${f.unwrapped(`packed.${f.name}()`)},${f.unwrapped(f.name)},"bad ${f.name}");`
      } 
    })}
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  ${s.fields.map(f =>
    format`function test_set_${f.name}(MgvStructs.${s.Packed} packed,${f.type} ${f.name}) public {
      MgvStructs.${s.Packed} original = packed.${f.name}(packed.${f.name}());
      assertEq(${f.unwrapped(`original.${f.name}()`)},${f.unwrapped(`packed.${f.name}()`)}, "original: bad ${f.name}");

      MgvStructs.${s.Packed} modified = packed.${f.name}(${f.name});

      ${(f.rawType === "uint" || f.rawType === "int") ?
        `assertEq(${f.unwrapped(`modified.${f.name}()`)},cast(${f.unwrapped(f.name)},${f.bits}),"modified: bad ${f.name}");`
        :
        `assertEq(${f.unwrapped(`modified.${f.name}()`)},${f.unwrapped(f.name)},"modified: bad ${f.name}");`
      }

      ${s.fields.filter(f2 => f2.name !== f.name).map(f2 =>
        `assertEq(${f2.unwrapped(`modified.${f2.name}()`)},${f2.unwrapped(`packed.${f2.name}()`)},"modified: bad ${f2.name}");`
      )}
    }`
  )}

  function test_unpack(MgvStructs.${s.Packed} packed) public {
    (${s.fields.map(f => `${f.type} ${f.name}`).join(", ")}) = packed.unpack();

    ${s.fields.map(f =>
      `assertEq(${f.unwrapped(`packed.${f.name}()`)},${f.unwrapped(f.name)},"bad ${f.name}");`
    )}
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(MgvStructs.${s.Packed} packed) public {
    MgvStructs.${s.Unpacked} memory unpacked = packed.to_struct();
    ${s.fields.map(f =>
      `assertEq(${f.unwrapped(`unpacked.${f.name}`)},${f.unwrapped(`packed.${f.name}()`)},"bad ${f.name}");`
    )}
  }

  function test_inverse_2(MgvStructs.${s.Unpacked} memory unpacked) public {
    MgvStructs.${s.Packed} packed = MgvStructs.${s.Name}.t_of_struct(unpacked);
    MgvStructs.${s.Packed} packed2;
    ${s.fields.map(f =>
      `packed2 = packed2.${f.name}(unpacked.${f.name});`
    )}
    ${s.fields.map(f =>
      `assertEq(${f.unwrapped(`packed.${f.name}()`)},${f.unwrapped(`packed2.${f.name}()`)},"bad ${f.name}");`
    )}
  }
}
`;
};
