// SPDX-License-Identifier: AGPL-3.0-or-later
import { format } from "./lib/format";

export const template = ({ preamble, structs }) => {
  return format`// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

${preamble}

${structs.map(s => {
  return `
import {${s.Packed}, ${s.Unpacked}, ${s.Lib}}  from "./${s.filenames.src}";`;
})}`;
};
