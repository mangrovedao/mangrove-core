/* ***** Mangrove tooling script ********* *
This script copies subsets of compiled artifacts to the distribution directory.

There are two possible subsets: just the abi, or abi+bytecode.

Note that the script only outputs contract names, not solidity files. It will
throw if you don't give it enough information to disambiguate. It will also
throw if you give it the same name in both exports lists.

Example contract names:

MyContract # naked contract name
MyFile.sol/MyContract2 # contract name qualified by file name

*/

const shell = require("shelljs");
shell.config.fatal = true; // throw if a command errors
const fs = require("fs");
const path = require("path");
const script = path.basename(__filename);
const config = require("./config.js");
const cwd = process.cwd();

const argv = require("yargs")
  .usage("$0")
  .version(false)
  .option("noop", {
    describe: "Dry run copy, do not modify files",
    type: "boolean",
  })
  .help().argv;

// set abi export directory (create if necessary), clear it
const distAbiDir = cwd + "/dist/abis/";
if (!argv.noop) {
  console.log(`${script}: Copying distribution assets...`);
  shell.rm("-rf", distAbiDir);
  shell.mkdir("-p", distAbiDir);
}

/* Utilities */

// recursively gather file paths in dir
let all_files = (dir, accumulator = []) => {
  for (const file_name of fs.readdirSync(dir)) {
    const file_path = path.join(dir, file_name);
    if (fs.statSync(file_path).isDirectory()) {
      all_files(file_path, accumulator);
    } else {
      accumulator.push(file_path);
    }
  }
  return accumulator;
};

// parse json file
const read_artifact = (file_path) => {
  return JSON.parse(fs.readFileSync(file_path, "utf8"));
};

// check that there name matches with exactly one element of artifacts
// return that element or throw otherwise
const match_path = (artifacts, name) => {
  const filtered = artifacts.filter((p) => p.endsWith(`/${name}.json`));
  if (filtered.length > 1) {
    throw new Error(
      `${script}: Ambiguous export name: ${name}, matched: ${filtered.toString()}`
    );
  }
  if (filtered.length === 0) {
    throw new Error(`${script}: Could not find a match for export ${name}`);
  }
  return filtered[0];
};

/* Script */
// list of data to export
const export_queue = [];

// gather all artifact files
const artifacts = all_files(path.join(cwd, "out"));

// combine all configured exports in a single list
const all_exports = config.abi_exports
  .map((name) => ({ export_type: "abi", name }))
  .concat(config.full_exports.map((name) => ({ export_type: "full", name })));

// add subset of full artifacts to export queue
for (const { name, export_type } of all_exports) {
  const match = match_path(artifacts, name);
  const artifact = read_artifact(match);
  let data;
  if (export_type === "abi") {
    data = { abi: artifact.abi };
  } else if (export_type === "full") {
    data = { abi: artifact.abi, bytecode: artifact.bytecode };
  } else {
    throw new Error(`${script}: Unknown export_type: ${export_type}`);
  }
  const basename = path.basename(match);
  export_queue.push({ name, match, basename, data });
}

// array of files written so far
const written = [];
// write each queued artifact subset
for (const { name, match, basename, data } of export_queue) {
  if (written.includes(basename)) {
    throw new Error(`${script}: Duplicate asset name: ${basename}`);
  }
  written.push(basename);
  const export_file = `${distAbiDir}/${basename}`;
  if (!argv.noop) {
    // since our git posthook seems to add trailing newlines (probably throuhg prettier),
    // not having one here means repeatedly seeing stripped newlines in git changes
    fs.writeFileSync(export_file, JSON.stringify(data, null, 2) + "\n");
  } else {
    console.log(`${script}: Matched ${name} with ${path.relative(cwd, match)}`);
    console.log(
      `${script}: Will export ${Object.keys(data)} to ${path.relative(
        cwd,
        export_file
      )}`
    );
    console.log();
  }
}
if (!argv.noop) {
  console.log(`${script}: ...Done copying distribution assets`);
}
