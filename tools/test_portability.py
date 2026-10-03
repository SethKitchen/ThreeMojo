# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free controls for native portability result handling."""

import os
import subprocess
import unittest
from unittest.mock import patch

import check_portability


class PortabilityTests(unittest.TestCase):
    def test_child_environment_does_not_inherit_roots_or_probe_actions(self):
        inherited = {'THREEMOJO_ASSET_ROOT': 'old', 'THREEMOJO_TEST_TMPDIR': 'old',
                     'THREEMOJO_PORTABILITY_FAIL': 'yes', 'TMPDIR': 'parent',
                     'PATH': '/bin'}
        with patch.dict(os.environ, inherited, clear=True):
            result = check_portability.environment(THREEMOJO_ASSET_ROOT='new')
        self.assertEqual(result, {'THREEMOJO_ASSET_ROOT': 'new',
                                 'TMPDIR': 'parent', 'PATH': '/bin'})

    def test_a_controlled_error_requires_both_nonzero_exit_and_diagnostic(self):
        for code, output, accepted in ((1, 'missing /root/file', True),
                                       (0, 'missing /root/file', False),
                                       (1, 'different failure', False),
                                       (-6, 'missing /root/file', False)):
            with self.subTest(code=code, output=output):
                result = subprocess.CompletedProcess(['probe'], code, output)
                with patch('check_portability.subprocess.run', return_value=result):
                    if accepted:
                        check_portability.run(['probe'], {}, '.', error='/root/file')
                    else:
                        with self.assertRaises(AssertionError):
                            check_portability.run(['probe'], {}, '.', error='/root/file')

    def test_success_requires_a_marker_and_the_original_five_second_limit(self):
        for code, output in ((0, ''), (1, 'PORTABILITY PASS')):
            with patch('check_portability.subprocess.run', return_value=
                       subprocess.CompletedProcess(['probe'], code, output)):
                with self.assertRaises(AssertionError):
                    check_portability.run(['probe'], {}, '.')
        with patch('check_portability.subprocess.run', return_value=
                   subprocess.CompletedProcess(['probe'], 0, 'PORTABILITY PASS')) as call:
            check_portability.run(['probe'], {}, '.')
            self.assertEqual(call.call_args.kwargs['timeout'], 5)

    def test_suite_output_cannot_hide_missing_or_slow_results(self):
        valid = ('Running 1 tests for suite.mojo\nPASS [ 1.0 ] test_a\n'
                 'Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped')
        for output, accepted in ((valid, True), ('', False),
                                  (valid.replace('PASS [ 1.0 ]', 'PASS [ 5001.0 ]'), False)):
            with patch('check_portability.subprocess.run', return_value=
                       subprocess.CompletedProcess(['probe'], 0, output)):
                if accepted:
                    check_portability.run(['probe'], {}, '.', suite=True)
                else:
                    with self.assertRaises(AssertionError):
                        check_portability.run(['probe'], {}, '.', suite=True)


if __name__ == '__main__':
    unittest.main()
