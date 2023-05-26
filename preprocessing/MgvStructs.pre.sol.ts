import { format } from "./lib/format";

export const template = ({ preamble, structs }) => {
  return format`// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

${preamble}

// Note: can't do Type.Unpacked because typechain mixes up multiple 'Unpacked' structs under different namespaces. So for consistency we don't do Type.Packed either. We do TypeUnpacked and TypePacked.

${structs.map(s => {
  return `
import {${s.Packed}, ${s.Unpacked}} from "./${s.filenames.src}";
import "./${s.filenames.src}" as ${s.Name};`;
})}`;
};
