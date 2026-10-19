# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the C ABI build wrapper with a stand-in compiler."""

import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest


BUILD = Path(__file__).resolve().parents[1] / "examples/capi/build.sh"


class CapiBuildTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="threemojo-capi-build-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.script = self.root / "examples/capi/build.sh"
        self.script.parent.mkdir(parents=True)
        self.script.write_bytes(BUILD.read_bytes())
        extension = "dylib" if platform.system() == "Darwin" else "so"
        self.output = self.root / f"out/capi/libthreemojo_core.{extension}"
        self.output.parent.mkdir(parents=True)
        self.compiler = self.root / "mojo"

    def run_build(self, compiler):
        self.compiler.write_text("#!/bin/sh\n" + compiler, encoding="utf-8")
        self.compiler.chmod(0o755)
        return subprocess.run(
            ["sh", str(self.script), "native"],
            env={**os.environ, "MOJO": str(self.compiler), "APPS": "core"},
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )

    def test_failed_compile_cannot_reuse_an_old_output(self):
        self.output.write_text("old library", encoding="utf-8")
        result = self.run_build('echo "compile failed" >&2\nexit 7\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("compile failed", result.stdout + result.stderr)
        self.assertNotIn("built into", result.stdout)

    def test_failed_compile_cannot_accept_a_partial_output(self):
        result = self.run_build('printf partial > "$7"\nexit 7\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("built into", result.stdout)

    def test_success_keeps_output_and_filters_the_crashpad_banner(self):
        result = self.run_build(
            'printf library > "$7"\n'
            'echo "Crashpad: reporter unavailable" >&2\n'
            'echo "compiler diagnostic" >&2\n'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "library")
        self.assertNotIn("Crashpad", result.stdout + result.stderr)
        self.assertIn("compiler diagnostic", result.stdout)

    def test_success_with_only_a_crashpad_banner_is_accepted(self):
        result = self.run_build(
            'printf library > "$7"\n'
            'echo "Crashpad: reporter unavailable" >&2\n'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_success_without_an_output_is_refused(self):
        result = self.run_build("exit 0\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mojo did not write", result.stderr)


if __name__ == "__main__":
    unittest.main()
