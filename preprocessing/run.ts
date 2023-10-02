import * as fs from "fs";

import struct_defs from "./structs";
import * as preproc from "./lib/preproc";
import { template as typeTemplate } from "./Struct.pre.sol";
import { template as testTemplate } from "./StructTest.pre.sol";
import { template as structsTemplate } from "./Structs.pre.sol";
import { template as toStringTemplate } from "./ToString.pre.sol";

const structs = preproc.make_structs(struct_defs, (struct) => ({
  src: `${struct.Name}.post.sol`,
  test: `${struct.Name}Test.post.sol`,
}));

const main = async () => {
  let processed = structsTemplate({ ...preproc, structs });
  fs.writeFileSync(`./src/preprocessed/Structs.post.sol`, processed);

  processed = toStringTemplate({... preproc, structs });
  fs.writeFileSync(`./lib/preprocessed/ToString.post.sol`, processed);

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
