# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for the cache key of each test suite."""

import contextlib
import io
import os
import tempfile
import unittest
from unittest.mock import patch

import affected
import suite_key

FILES = {
    "Makefile": "all:\n",
    "tools/affected.py": "",
    "tools/run_suite.py": "",
    "tools/suite_key.py": "",
    "pkg/__init__.mojo": "",
    "pkg/used.mojo": "from pkg.deep import f\n",
    "pkg/deep.mojo": "def f():\n    pass\n",
    "pkg/unused.mojo": "def g():\n    pass\n",
    "tests/test_x.mojo": 'from pkg.used import f\n\ndef test_a():\n    _ = "assets/box/"\n',
    "assets/box/a.bin": "1",
    "assets/other.bin": "2",
}


class SuiteKeyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name
        for path, text in FILES.items():
            self.write(path, text)
        patcher = patch.object(affected, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.directory.cleanup)

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(text)

    def key(self, settings=("s",)):
        known = set(affected.mojo_files())
        return suite_key.suite_key(
            "tests/test_x.mojo", list(settings), known, {},
            suite_key.asset_files(), {})

    def test_closure_follows_imports_and_packages(self):
        known = set(affected.mojo_files())
        self.assertEqual(
            suite_key.closure("tests/test_x.mojo", known, {}),
            ["pkg/__init__.mojo", "pkg/deep.mojo", "pkg/used.mojo",
             "tests/test_x.mojo"])

    def test_key_is_stable(self):
        self.assertEqual(self.key(), self.key())

    def test_reached_files_quoted_assets_tools_and_settings_change_the_key(self):
        before = self.key()
        for path in ("pkg/deep.mojo", "assets/box/a.bin", "Makefile",
                     "tools/run_suite.py"):
            self.write(path, "changed")
            after = self.key()
            self.assertNotEqual(before, after, path)
            before = after
        self.assertNotEqual(before, self.key(("t",)))

    def test_unreached_files_and_assets_leave_the_key(self):
        before = self.key()
        self.write("pkg/unused.mojo", "changed")
        self.write("assets/other.bin", "changed")
        self.assertEqual(before, self.key())

    def test_prints_only_the_suites_without_a_stamp(self):
        stamps = os.path.join(self.root, "stamps")
        os.makedirs(stamps)
        args = ["--stamps", stamps, "--setting=s", "tests/test_x.mojo"]
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            suite_key.main(args)
        suite, key = out.getvalue().split()
        self.assertEqual((suite, key), ("tests/test_x.mojo", self.key()))
        open(os.path.join(stamps, "test_x-" + key), "w").close()
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            suite_key.main(args)
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
