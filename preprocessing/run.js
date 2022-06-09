const fs = require('fs');
const solpp = require('solpp');
const path = require('path');

const defs = require('./structs.js');

const PRE = (name) => `./preprocessing/${name}`;
const POST = (name) => `./contracts/preprocessed/${name}`;

const opts_for = (ns) => {
  return {
    defs: {ns, ...defs},
    noFlatten: true
  }
};

const run_process = async (pre_file, post_file, ns) => {
  const processed = await solpp.processFile(pre_file, opts_for(ns));
  fs.writeFileSync(post_file,processed);
}

const main = async () => {

  await run_process(
    PRE('MgvPack.pre.sol'),
    POST('MgvPack.post.sol'),
    undefined
  );

  await run_process(
    PRE('MgvStructs.pre.sol'),
    POST('MgvStructs.post.sol'),
    undefined
  );

  for (const ns of defs.struct_defs) {
    await run_process(
      PRE('MgvType.pre.sol'),
      POST(defs.filename(ns)),
      ns
    );
  }

}

main().then(() => process.exit()).catch(e => { console.error(e); process.exit(1); });