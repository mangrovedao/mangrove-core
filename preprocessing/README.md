# Preprocessing

Mangrove data are packed even outside of storage to save gas.

`structs.js` contains the structures. It uses `lib/preproc.js` to generate preprocessing instructions.

`run.js` loads `structs.js`, then uses `solpp` to process `.pre.sol` files into `.sol` files. The `.pre.sol` files are described in `contracts/preprocessed/README.md`.

To run preprocessing, use the task `preproc` in `package.json`.





