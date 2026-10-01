# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Opt-in ALL diagnostics must not alter Make-consumed stdout."""

import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import affected


class AffectedDiagnosticsTests(unittest.TestCase):
    def run_selection(self, changed, verbose, extra=(), old_source=''):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'tests').mkdir()
            (root / 'tests/test_a.mojo').write_text('def test_a():\n    pass\n')
            output, errors = io.StringIO(), io.StringIO()
            args = ['affected.py', '--base', 'main', *extra]
            if verbose:
                args.append('--verbose')
            args += ['tests/test_a.mojo', 'core/other.mojo']
            with patch.object(affected, 'ROOT', folder), \
                    patch.object(affected, 'changed_paths', return_value=changed), \
                    patch.object(affected, 'git', side_effect=['revision\n', 'tests/test_a.mojo\0', old_source]), \
                    patch.object(sys, 'argv', args), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(affected.main(), 0)
            return output.getvalue(), errors.getvalue()

    def test_all_reasons_preserve_stdout_and_are_opt_in(self):
        cases = [
            (None, '', 'Git could not establish'),
            ({'tools/build.py': False}, '', 'no narrower dependency rule'),
            ({'tests/test_a.mojo': True}, '', 'was deleted'),
            ({'tests/test_a.mojo': False}, 'from core.old import old\n', 'removed imports'),
        ]
        for changed, old, reason in cases:
            for extra in ((), ('--list',), ('--changed',)):
                with self.subTest(changed=changed, extra=extra):
                    plain = self.run_selection(changed, False, extra, old)
                    verbose = self.run_selection(changed, True, extra, old)
                    self.assertEqual(plain[0], verbose[0])
                    self.assertEqual(plain[1], '')
                    self.assertIn(reason, verbose[1])

    def test_narrow_selection_does_not_claim_an_all_fallback(self):
        for changed in ({}, {'README.md': False}, {'tests/test_a.mojo': False}):
            plain = self.run_selection(changed, False)
            verbose = self.run_selection(changed, True)
            self.assertEqual(plain, verbose)
            self.assertEqual(verbose[1], '')

    def test_unknown_baseline_has_an_explicit_reason(self):
        reasons = []
        with patch.object(affected, 'git', return_value=None):
            self.assertTrue(affected.test_imports_removed({'tests/test_a.mojo': False}, 'main', reasons))
        self.assertEqual(reasons, ['the test import baseline could not be established'])


if __name__ == '__main__':
    unittest.main()
