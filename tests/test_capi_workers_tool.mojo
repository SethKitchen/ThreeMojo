# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check worker cleanup when a WebAssembly thread pool cannot start.

Node runs `examples/capi/web/threemojo.js` with a stand-in WebAssembly
runtime. A missing Node skips the check.
"""

from std.os.path import realpath
from std.testing import TestSuite, assert_equal

from tools._process import run_program


def _script() -> String:
    """Return the Node program that drives each failure.

    Returns:
        A module that imports the page's thread loader.
    """
    return """
import assert from "node:assert/strict";
const { loadThreads } = await import(process.argv[1]);
const scenario = process.argv[2];
const workers = [];
let stacks = 0;
WebAssembly.compile = async () => ({});
WebAssembly.Memory = class {
  constructor() { this.buffer = new SharedArrayBuffer(16); }
};
WebAssembly.Instance = class {
  constructor() {
    this.exports = {
      mw_set_threads(count) { assert.equal(count, 3); },
      mw_stack() {
        stacks++;
        return scenario === "stack" && stacks === 2 ? 0 : stacks * 4096;
      },
      tm_abi_version() { return scenario === "abi" ? -1 : 1; },
      tm_init() { if (scenario === "init") throw new Error("init failed"); },
    };
  }
};
const spawn = () => {
  if (scenario === "spawn" && workers.length === 1) throw new Error("spawn failed");
  const worker = {
    posts: 0,
    stops: 0,
    postMessage() {
      this.posts++;
      if (scenario === "post" && workers.length === 2) throw new Error("post failed");
    },
    terminate() { this.stops++; },
  };
  workers.push(worker);
  return worker;
};
const messages = {
  stack: /no room for the stack/,
  spawn: /spawn failed/,
  post: /post failed/,
  abi: /module has ABI -1/,
  init: /init failed/,
};
if (scenario === "success") {
  const library = await loadThreads(new Uint8Array(), { threads: 2, spawn });
  assert.equal(workers.length, 2);
  assert.deepEqual(workers.map((worker) => worker.posts), [1, 1]);
  assert.deepEqual(workers.map((worker) => worker.stops), [0, 0]);
  library.close();
  assert.deepEqual(workers.map((worker) => worker.stops), [1, 1]);
} else {
  await assert.rejects(loadThreads(new Uint8Array(), { threads: 2, spawn }), messages[scenario]);
  assert.equal(workers.length, scenario === "stack" || scenario === "spawn" ? 1 : 2);
  assert.deepEqual(workers.map((worker) => worker.stops), workers.map(() => 1));
}
"""


def test_startup_cleanup_and_successful_close() raises:
    var found = run_program(["sh", "-c", "command -v node"], 5)
    if found.status != 0:
        print("SKIP (no node): C ABI worker cleanup")
        return
    var node = String(found.output.split("\n")[0])
    var library = "file://" + realpath("examples/capi/web/threemojo.js")
    var script = _script()
    for scenario in [
        "stack",
        "spawn",
        "post",
        "abi",
        "init",
        "success",
    ]:
        var result = run_program(
            [
                node,
                "--input-type=module",
                "-e",
                script,
                library,
                scenario,
            ],
            10,
        )
        assert_equal(
            result.status, 0, scenario + "\n" + result.output + result.errors
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
