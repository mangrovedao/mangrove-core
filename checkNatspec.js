/* ********* Mangrove tooling script ********* *
This script verifies that select files have natspec comments for all parameters and return values of functions
*/

// TODO: In forge 0.2.0 (d58ab7f 2024-02-27T00:16:43.649244000Z), this script no longer works:
// The generated JSON files no longer have an AST field.

const fs = require("fs");
const path = require("path");
const cwd = process.cwd();

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

// gather all artifact files
const artifacts = all_files(path.join(cwd, "out"));

includes = ["TransferLib", "IMangrove"];

let anyFindings = false;
artifacts.forEach((file) => {
  if (!includes.some((x) => file.includes("/" + x + ".sol"))) {
    return;
  }
  const j = read_artifact(file);
  const fname = j.ast.absolutePath;
  const relevant = j.ast.nodes
    .filter((x) => x.nodeType == "ContractDefinition")
    .map((x) => {
      if (!x.documentation.text.includes("@title")) {
        anyFindings = true;
        console.log(`${fname} - ${x.name} missing @title`);
      }
      return x.nodes;
    })
    .flat();

  relevant
    .filter(
      (x) =>
        x.nodeType == "FunctionDefinition" ||
        x.nodeType == "EventDefinition" ||
        x.nodeType == "VariableDeclaration",
    )
    .forEach((x) => {
      const doc = x?.documentation?.text ?? "";
      if (doc.includes("@inheritdoc")) {
        return;
      }

      const name = x?.kind == "constructor" ? "constructor" : x.name;
      if (!doc.includes("@notice")) {
        anyFindings = true;
        console.log(`${fname}: ${name} - no description`);
      }
      x.returnParameters?.parameters.forEach((p) => {
        if (!doc.includes(`@return ${p.name}`)) {
          anyFindings = true;
          console.log(`${fname}: ${name} - ${p.name} (return)`);
        }
      });
      x.parameters?.parameters.forEach((p) => {
        if (!doc.includes(`@param ${p.name}`)) {
          anyFindings = true;
          console.log(`${fname}: ${name} - ${p.name}`);
        }
      });
    });
});

if (anyFindings) {
  throw new Error("Found missing natspec comments");
}
