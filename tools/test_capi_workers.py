# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check worker cleanup when a WebAssembly thread pool cannot start."""

from pathlib import Path
import shutil
import subprocess
import unittest


LIBRARY = Path(__file__).resolve().parents[1] / "examples/capi/web/threemojo.js"
CHECK = r"""
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


class CapiWorkerTests(unittest.TestCase):
    def test_startup_cleanup_and_successful_close(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("the JavaScript wrapper test needs Node")
        for scenario in ("stack", "spawn", "post", "abi", "init", "success"):
            with self.subTest(scenario=scenario):
                result = subprocess.run(
                    [node, "--input-type=module", "-e", CHECK, LIBRARY.as_uri(), scenario],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
