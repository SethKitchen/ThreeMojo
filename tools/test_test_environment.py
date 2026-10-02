# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Isolation, cleanup and TMPDIR regressions for test processes."""

import os
from pathlib import Path
import tempfile
import sys

import coverage_io
import unittest
from unittest.mock import patch

from test_environment import isolated_environment


class EnvironmentTests(unittest.TestCase):
    def test_distinct_roots_honor_tmpdir_and_cleanup(self):
        with tempfile.TemporaryDirectory() as parent:
            with patch.dict(os.environ, {'TMPDIR': parent}):
                with isolated_environment() as a, isolated_environment() as b:
                    one = Path(a['THREEMOJO_TEST_TMPDIR'])
                    two = Path(b['THREEMOJO_TEST_TMPDIR'])
                    self.assertNotEqual(one, two)
                    self.assertEqual(one.parent, Path(parent).resolve())
                    self.assertEqual(a['TMPDIR'], str(one))
                    (one / 'same.bin').write_text('one')
                    (two / 'same.bin').write_text('two')
                    self.assertEqual((one / 'same.bin').read_text(), 'one')
                self.assertFalse(one.exists())
                self.assertFalse(two.exists())

    def test_symlink_tmpdir_resolves_roots_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as folder:
            parent = Path(folder) / 'parent'
            parent.mkdir()
            alias = Path(folder) / 'alias'
            alias.symlink_to(parent, target_is_directory=True)
            with patch.dict(os.environ, {'TMPDIR': str(alias)}):
                with isolated_environment() as a, isolated_environment() as b:
                    one = Path(a['THREEMOJO_TEST_TMPDIR'])
                    two = Path(b['THREEMOJO_TEST_TMPDIR'])
                    self.assertNotEqual(one, two)
                    for root, env in ((one, a), (two, b)):
                        self.assertEqual(root.parent, parent.resolve())
                        self.assertTrue(root.parent.samefile(alias))
                        self.assertEqual(env['TMPDIR'], str(root))
                        (root / 'fixture.bin').write_bytes(b'fixture')
                self.assertFalse(one.exists())
                self.assertFalse(two.exists())
            self.assertTrue(parent.is_dir())
            self.assertTrue(alias.is_symlink())
            self.assertEqual(list(parent.iterdir()), [])

    def test_coverage_capture_cleans_success_and_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            parent = Path(folder)
            marker = parent / 'root.txt'
            for status in (0, 3):
                program = (
                    "import os,pathlib; "
                    "root=os.environ['THREEMOJO_TEST_TMPDIR']; "
                    f"pathlib.Path({str(marker)!r}).write_text(root); "
                    "pathlib.Path(root, 'fixture.bin').write_bytes(b'fixture'); "
                    f"raise SystemExit({status})")
                self.assertEqual(coverage_io.capture(
                    [sys.executable, '-c', program], parent / 'capture.out',
                    parent / 'capture.gz'), status)
                self.assertFalse(Path(marker.read_text()).exists())

    def test_exception_still_cleans_up(self):
        with self.assertRaisesRegex(RuntimeError, 'failure'):
            with isolated_environment() as env:
                root = Path(env['THREEMOJO_TEST_TMPDIR'])
                (root / 'leftover').write_text('x')
                raise RuntimeError('failure')
        self.assertFalse(root.exists())


if __name__ == '__main__':
    unittest.main()
