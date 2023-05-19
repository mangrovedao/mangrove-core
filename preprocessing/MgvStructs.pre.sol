// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

$(preamble)

// Note: can't do Type.Unpacked because typechain mixes up multiple 'Unpacked' structs under different namespaces. So for consistency we don't do Type.Packed either. We do TypeUnpacked and TypePacked.

// #for ns in struct_defs
// #def sname ns[0]
// #def Sname capitalize(ns[0])
// #def struct_def ns[1]
$$(concat('import {',Sname,'Packed, ',Sname, 'Unpacked} from \"./',filename(ns),'\"'));
$$(concat('import \"./',filename(ns),'\" as ',Sname));
// #done
// #def __x avoid_solpp_eof_error_by_adding_useless_line
