# Preprocessing

Mangrove data are packed even outside of storage to save gas.

`structs.ts` contains the structures. It uses `lib/preproc.ts` to generate preprocessing instructions.

`run.ts` loads `structs.js`, then uses processes `.pre.sol.ts` files into `.post.sol` files. The `.pre.sol` files are described in `contracts/preprocessed/README.md`.

To run preprocessing, use the task `preproc` in `package.json`.
