import * as fs from 'fs';

import struct_defs from "./structs";
import * as preproc from "./lib/preproc";
import { template as typeTemplate } from "./MgvType.pre.sol";
import { template as structsTemplate } from "./MgvStructs.pre.sol";

// const run_preproc = async (pre_file, post_file, args) => {
//   const template = (await import(`./${pre_file}`)).template as (...args: any[]) => string;
//   const processed = template(args);
//   fs.writeFileSync(`./src/preprocessed/${post_file}`, processed);
// };

const structs = preproc.make_structs(
  struct_defs,
  (struct) => `Mgv${struct.Name}.post.sol`
);

const main = async () => {
  const processed = structsTemplate({...preproc, structs});
  fs.writeFileSync(`./src/preprocessed/MgvStructs.post.sol`, processed);

  for (const struct of structs) {
    const processed = typeTemplate({...preproc, struct});
    fs.writeFileSync(`./src/preprocessed/${struct.filename}`, processed);
  }
};

main()
  .then(() => process.exit())
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
