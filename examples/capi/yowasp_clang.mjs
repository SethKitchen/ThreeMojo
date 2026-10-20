// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// Run @yowasp/clang with a clang command line. yowasp_clang.sh calls this.
// The package runs clang in a file system of its own: each file that the
// command line names is read into it, and the file after -o is written back.
// "-o -" writes to the standard output. YOWASP_CLANG names the package's
// gen/bundle.js when it is not under out/capi/yowasp.
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const bundle = process.env.YOWASP_CLANG ??
  join(here, "../../out/capi/yowasp/node_modules/@yowasp/clang/gen/bundle.js");
if (!existsSync(bundle)) {
  console.error(`yowasp_clang: no ${bundle}; run npm install --prefix out/capi/yowasp @yowasp/clang`);
  process.exit(2);
}
const { runClang } = await import(bundle);

const tree = {};
const args = [];
let output = null;
const given = process.argv.slice(2);
for (let index = 0; index < given.length; index++) {
  const word = given[index];
  if (word === "-o") {
    output = given[++index];
    args.push("-o", "out.result");
  } else if (word === "/dev/null") {
    tree["null.c"] = "";
    args.push("null.c");
  } else if (!word.startsWith("-") && existsSync(word) && statSync(word).isFile()) {
    const name = `in${Object.keys(tree).length}_${basename(word)}`;
    tree[name] = readFileSync(word);
    args.push(name);
  } else {
    args.push(word);
  }
}

let files;
try {
  files = await runClang(["clang", ...args], tree, {
    stdout: (bytes) => bytes && process.stdout.write(bytes),
    stderr: (bytes) => bytes && process.stderr.write(bytes),
    fetchProgress: () => {},
  });
} catch (error) {
  if (error.code !== undefined) process.exit(error.code);
  throw error;
}
if (output === "-") process.stdout.write(files["out.result"]);
else if (output) writeFileSync(output, files["out.result"]);
