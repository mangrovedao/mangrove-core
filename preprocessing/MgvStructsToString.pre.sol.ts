import { format } from "./lib/format";


export const template = ({ preamble, structs }) => {
  return format`// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

${preamble}

// Avoid name shadowing
import "../MiscToString.sol";

${structs.map(s => {

  const fields = s.fields.map(f => {
    if (f.userDefined) {
      return `"${f.name}: ", toString(__unpacked.${f.name})`;
    } else {
      return `"${f.name}: ", vm.toString(__unpacked.${f.name})`;
    }
  });
  const elements = `"${s.Name}{",${fields.join(', ", ", ')},"}"`;

  return `
  import {${s.Packed}, ${s.Unpacked}} from "mgv_src/preprocessed/${s.filenames.src}";
  function toString(${s.Packed} __packed) pure returns (string memory) {
    return toString(__packed.to_struct());
  }

  function toString(${s.Unpacked} memory __unpacked) pure returns (string memory) {
    return string.concat(${elements});
  }`;
})}`;
}
