const { format, tabulate } = require("./lib/format.js");

exports.template = ({ preamble, struct_utilities, struct: s }) => {
  return format`// ${s.filename}

// SPDX-License-Identifier: Unlicense

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

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

// number of bits in each field
${tabulate(s.fields.map(f => 
  [`uint constant ${f.vars.bits}`, ` = ${f.bits};`]
))}

// number of bits before each field
${tabulate(s.fields.map((f,i) => {
    const { before, bits } = i ? s.fields[i - 1].vars : { before: 0, bits: 0 };
    return [`uint constant ${f.vars.before}`, ` = ${before}`, ` + ${bits};`];
}))}

// cleanup-mask: 0s at field location, 1s elsewhere
${tabulate(s.fields.map(f => 
  [`uint constant ${f.vars.mask}`, ` = ${f.mask()};`]
))}

library Library {
  function to_struct(${s.Packed} __packed) internal pure returns (${s.Unpacked} memory __s) { unchecked {
    ${tabulate(s.fields.map(f => 
      [`__s.${f.name}`, ` = ${f.extract(s.unwrap("__packed"))};`, ]
    ))}
  }}

  function eq(${s.Packed} __packed1, ${s.Packed} __packed2) internal pure returns (bool) { unchecked {
    return ${s.unwrap("__packed1")} == ${s.unwrap("__packed2")};
  }}

  function unpack(${s.Packed} __packed) internal pure returns (${s.fields.map(f => `${f.type} __${f.name}`).join(", ")}) { unchecked {
    ${tabulate(s.fields.map(f => 
      [`__${f.name}`,` = ${f.extract(s.unwrap("__packed"))};`, ]
    ))}
  }}

  ${s.fields.map(f =>
  `function ${f.name}(${s.Packed} __packed) internal pure returns(${f.type}) { unchecked {
    return ${f.extract(s.unwrap("__packed"))};
  }}

  function ${f.name}(${s.Packed} __packed,${f.type} val) internal pure returns(${s.Packed}) { unchecked {
    uint __clean_struct = ${s.unwrap("__packed")} & ${f.vars.mask};
    uint __clean_field  = ${f.inject("val")};
    return ${s.wrap("__clean_struct | __clean_field")};
  }}
  `
  )}
}

function t_of_struct(${s.Unpacked} memory __s) pure returns (${s.Packed}) { unchecked {
  return pack(${s.fields.map(f => `__s.${f.name}`).join(", ")});
}}

function pack(${s.fields.map(f => `${f.type} __${f.name}`).join(", ")}) pure returns (${s.Packed}) { unchecked {
  uint __packed = 0;
  ${s.fields.map(f => `__packed |= ${f.inject(`__${f.name}`)};`)}
  return ${s.wrap("__packed")};
}}
`;
};
