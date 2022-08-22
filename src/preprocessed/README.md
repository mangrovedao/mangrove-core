# Preprocessed Mangrove files

For more on the processing setuyp, see `mangrove-solidity/preprocessing`.

Processed file organisation is a little complicated due to the following constraints: 

1) We want processed library to be accessed through dot-syntax e.g. `Processed.Struct.method`. 
2) We want file-level Solidity user-defined types, because, as of 0.8.14, this is the only way to enable syntactic sugar (through `using ... for`) globally; otherwise consumers of processed file would have to repeat the `using` directives.

Given these 2 constraints, we generate:
* A single `MgvPack.post.sol` imported under the namespace `P` by `MgvLib.sol`.
* A single `MgvStructs.post.sol` imported by `MgvPack.post.sol` and each individual file, containing struct definitions.
* Multiple `Mgv<Type>.post.sol`, imported under the namespace `<Type>` by `MgvPack.post.sol`.

Together, this means we can access the user-defined types `P.<Type>.t` automatically after importing `MgvLib.sol`.
