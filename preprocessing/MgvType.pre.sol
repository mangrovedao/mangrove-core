// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

// fields are of the form [name,bits,type]

// struct_defs are of the form [name,obj]
// #def sname ns[0]
// #def Sname capitalize(ns[0])
// #def struct_def ns[1]

$(preamble)

/* since you can't convert bool to uint in an expression without conditionals, 
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly { u := b }
}

struct $$(Sname)Unpacked {
  $$(join(map(struct_def,(field) => `$${f_type(field)} $${f_name(field)};`),`\n$${__indent}`))
}

//some type safety for each struct
type $$(Sname)Packed is uint;
using Library for $$(Sname)Packed global;

// #for field in struct_def
uint constant $$(f_bits_cst(field,struct_def)) = $$(f_bits(field));
// #done

// #for field in struct_def
uint constant $$(f_before_cst(field,struct_def)) = $$(f_before_formula(field,struct_def));
// #done

// #for field in struct_def
uint constant $$(f_mask_cst(field,struct_def)) = $$(f_mask(field,struct_def));
// #done

library Library {
  function to_struct($$(Sname)Packed __packed) internal pure returns ($$(Sname)Unpacked memory __s) { unchecked {
    // #for field in struct_def
    __s.$$(f_name(field)) = $$(get(concat(Sname,'Packed.unwrap(__packed)'),struct_def,f_name(field)));
    // #done
  }}

  function eq($$(Sname)Packed __packed1, $$(Sname)Packed __packed2) internal pure returns (bool) { unchecked {
    return $$(Sname)Packed.unwrap(__packed1) == $$(Sname)Packed.unwrap(__packed2);
  }}

/* #def arguments
  join(map(struct_def,(field) => `$${f_type(field)} __$${f_name(field)}`),', ')
*/


  function unpack($$(Sname)Packed __packed) internal pure returns ($$(arguments)) { unchecked {
    // #for field in struct_def
    __$$(f_name(field)) = $$(get(concat(Sname,'Packed.unwrap(__packed)'),struct_def,f_name(field)));
    // #done
  }}

  // #for field in struct_def
  function $$(f_name(field))($$(Sname)Packed __packed) internal pure returns($$(f_type(field))) { unchecked {
    return $$(get(concat(Sname,'Packed.unwrap(__packed)'),struct_def,f_name(field)));
  }}
  function $$(f_name(field))($$(Sname)Packed __packed,$$(f_type(field)) val) internal pure returns($$(Sname)Packed) { unchecked {
    return $$(Sname)Packed.wrap($$(set1(concat(Sname,'Packed.unwrap(__packed)'),struct_def,f_name(field),'val',__indent)));
  }}
  // #done
}

function t_of_struct($$(Sname)Unpacked memory __s) pure returns ($$(Sname)Packed) { unchecked {
  return pack($$(join(map(struct_def,(field) => `__s.$${f_name(field)}`),', ')));
}}

function pack($$(arguments)) pure returns ($$(Sname)Packed) { unchecked {
  return $$(Sname)Packed.wrap($$(make(
    struct_def,
    map(struct_def, (field) =>
  [f_name(field),`__$${f_name(field)}`]),__indent)));
}}