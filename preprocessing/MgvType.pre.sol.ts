// TODO Try to reduce codesize by having all functions go through a common parametric "modify there" function
import { format, tabulate } from "./lib/format";

export const template = ({ preamble, struct_utilities, struct: s }) => {
  return format`// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

${preamble}

${struct_utilities}

struct ${s.Unpacked} {
  ${s.fields.map(f => 
    `${f.type} ${f.name};`
  )}
}

//some type safety for each struct
type ${s.Packed} is uint;
using Library for ${s.Packed} global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////
${s.additionalDefinitions ?? ''}
////////////// END OF ADDITIONAL DEFINITIONS /////////////////

// number of bits in each field
${tabulate(s.fields.map(f => 
  [`uint constant ${f.vars.bits}`, ` = ${f.bits};`]
))}

// number of bits before each field
${tabulate(s.fields.map((f,i) => {
    const { before, bits } = i ? s.fields[i - 1].vars : { before: 0, bits: 0 };
    return [`uint constant ${f.vars.before}`, ` = ${before}`, ` + ${bits};`];
}))}

// focus-mask: 1s at field location, 0s elsewhere
${tabulate(s.fields.map(f => 
  [`uint constant ${f.vars.mask_inv}`, ` = ${f.mask_inv};`]
))}

// cleanup-mask: 0s at field location, 1s elsewhere
${tabulate(s.fields.map(f => 
  [`uint constant ${f.vars.mask}`, ` = ${f.mask};`]
))}

library Library {
  // from packed to in-memory struct
  function to_struct(${s.Packed} __packed) internal pure returns (${s.Unpacked} memory __s) { unchecked {
    ${tabulate(s.fields.map(f => 
      [`__s.${f.name}`, ` = ${f.extract(s.unwrap("__packed"))};`, ]
    ))}
  }}

  // equality checking
  function eq(${s.Packed} __packed1, ${s.Packed} __packed2) internal pure returns (bool) { unchecked {
    return ${s.unwrap("__packed1")} == ${s.unwrap("__packed2")};
  }}

  // from packed to a tuple
  function unpack(${s.Packed} __packed) internal pure returns (${s.fields.map(f => `${f.type} __${f.name}`).join(", ")}) { unchecked {
    ${tabulate(s.fields.map(f => 
      [`__${f.name}`,` = ${f.extract(s.unwrap("__packed"))};`, ]
    ))}
  }}

  // getters
  ${s.fields.map(f =>
  `function ${f.name}(${s.Packed} __packed) internal pure returns(${f.type}) { unchecked {
    return ${f.extract(s.unwrap("__packed"))};
  }}

  // setters
  function ${f.name}(${s.Packed} __packed,${f.type} val) internal pure returns(${s.Packed}) { unchecked {
    return ${s.wrap(`(${s.unwrap("__packed")} & ${f.vars.mask}) | ${f.inject("val")}`)};
  }}
  `
  )}
}

// from in-memory struct to packed
function t_of_struct(${s.Unpacked} memory __s) pure returns (${s.Packed}) { unchecked {
  return pack(${s.fields.map(f => `__s.${f.name}`).join(", ")});
}}

// from arguments to packed
function pack(${s.fields.map(f => `${f.type} __${f.name}`).join(", ")}) pure returns (${s.Packed}) { unchecked {
  uint __packed;
  ${s.fields.map(f => `__packed |= ${f.inject(`__${f.name}`)};`)}
  return ${s.wrap("__packed")};
}}
`;
};