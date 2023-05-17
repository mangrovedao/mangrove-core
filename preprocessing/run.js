const fs = require("fs");

const run_preproc = async (pre_file, post_file, args) => {
  const { template } = require(`./${pre_file}`);
  const processed = template(args);
  fs.writeFileSync(`./src/preprocessed/${post_file}`, processed);
};

const struct_defs = require("./structs.js");
const preproc = require("./lib/preproc.js");

const structs = preproc.make_structs(
  struct_defs,
  (struct) => `Mgv${struct.Name}.post.sol`
);

const main = async () => {
  await run_preproc("MgvStructs.pre.sol.js", "MgvStructs.post.sol", {
    ...preproc,
    structs,
  });

  for (const struct of structs) {
    await run_preproc("MgvType.pre.sol.js", struct.filename, {
      ...preproc,
      struct,
    });
  }
};

main()
  .then(() => process.exit())
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
