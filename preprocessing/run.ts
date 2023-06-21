import * as fs from "fs";

import struct_defs from "./structs";
import * as preproc from "./lib/preproc";
import { template as typeTemplate } from "./MgvType.pre.sol";
import { template as testTemplate } from "./MgvTypeTest.pre.sol";
import { template as structsTemplate } from "./MgvStructs.pre.sol";
import { template as toStringTemplate } from "./MgvStructsToString.pre.sol";

const structs = preproc.make_structs(struct_defs, (struct) => ({
  src: `Mgv${struct.Name}.post.sol`,
  test: `Mgv${struct.Name}Test.post.sol`,
}));

const main = async () => {
  let processed = structsTemplate({ ...preproc, structs });
  fs.writeFileSync(`./src/preprocessed/MgvStructs.post.sol`, processed);

  processed = toStringTemplate({... preproc, structs });
  fs.writeFileSync(`./lib/preprocessed/MgvStructsToString.post.sol`, processed);

  for (const struct of structs) {
    const processed = typeTemplate({ ...preproc, struct });
    fs.writeFileSync(`./src/preprocessed/${struct.filenames.src}`, processed);
  }

  for (const struct of structs) {
    const processed = testTemplate({ ...preproc, struct });
    fs.writeFileSync(`./test/preprocessed/${struct.filenames.test}`, processed);
  }
};

main()
  .then(() => process.exit())
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
