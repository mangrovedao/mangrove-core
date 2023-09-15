# Preprocessed Mangrove files

For more on the processing setup, see `preprocessing/`.

Processed file organisation is a little complicated due to the following constraints:

1. We want processed libraries to be accessed through dot-syntax e.g. `MgvStructs.Struct.method`.
2. We want file-level Solidity user-defined types, because, as of 0.8.14, this is the only way to enable syntactic sugar (through `using ... for`) globally; otherwise consumers of processed file would have to repeat the `using` directives.

The import hierarchy is as follows:

- `MgvLib.sol` imports `MgvStructs.post.sol`, as `MgvStructs`.
- For each struct in `structs.ts` there is a `Mgv<Struct>.post.sol` file. It contains a library and file-level functions related to the struct.
- `MgvStructs.post.sol` imports each `Mgv<Struct>.post.sol` in two ways:
  - It imports the user-defined type `<Struct>Packed` and the struct `<Struct>Unpacked` by name.
  - The entire file is imported `as <Struct>`.

Taken together this means we can write `MgvStructs.OfferPacked.wrap(x)` and `MgvStructs.OfferUnpacked s = ...`, and `MgvStructs.Offer.pack(...args)`.
