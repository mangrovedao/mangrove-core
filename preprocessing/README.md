# Preprocessing

Mangrove data are packed even outside of storage to save gas.

`structs.js` contains the structures. It uses `lib/preproc.js` to generate preprocessing instructions.

`MgvPack.pre.sol` contains a solidity file to be processed. The parent's folder `yarn preproc` task copies the output of processing `MgvPack.pre.sol` to `contracts/MgvPack.sol`.
