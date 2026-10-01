# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for the time limit on each test of a suite."""

import os
from pathlib import Path
import sys
import tempfile
import unittest

import run_suite

OUTPUT = (
    "\x1b[92mRunning\x1b[0m 3 tests for tests/test_a.mojo\n"
    "    \x1b[92mPASS\x1b[0m [ 4999.000 ] test_fast\n"
    "    \x1b[91mFAIL\x1b[0m [ 5000.500 ] test_slow\n"
    "    PASS [ 12.000 ] test_quick\n"
    "--------\n"
    "Summary [ 10011.500 ] 3 tests run: 2 passed , 1 failed , 0 skipped\n"
)


def successful_output(name='test_a', milliseconds=1):
    return (f'Running 1 tests for suite.mojo\n'
            f'    PASS [ {milliseconds}.0 ] {name}\n'
            'Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped')


class RunSuiteTests(unittest.TestCase):
    def test_counts_only_test_functions(self):
        text = "def test_a() raises:\n    pass\n\ndef helper():\n    pass\n" \
               "def test_b():\n    pass\n    def test_nested():\n        pass\n"
        self.assertEqual(run_suite.count_tests(text), 2)

    def test_reports_each_result_over_the_limit(self):
        self.assertEqual(run_suite.slow_tests(OUTPUT, 5.0), [("test_slow", 5.0005)])
        self.assertEqual(run_suite.slow_tests(OUTPUT, 6.0), [])

    def test_budget_covers_every_test_and_startup(self):
        self.assertEqual(run_suite.budget(5.0, 3), 20.0)
        self.assertEqual(run_suite.budget(5.0, 0), 10.0)

    def _run(self, seconds, program):
        with tempfile.TemporaryDirectory() as directory:
            suite = os.path.join(directory, "test_a.mojo")
            with open(suite, "w", encoding="utf-8") as source:
                source.write("def test_a():\n    pass\n")
            return run_suite.main([
                "--seconds", str(seconds), "--suite", suite, "--",
                sys.executable, "-c", program,
            ])

    def test_passes_a_fast_suite(self):
        self.assertEqual(self._run(5, f"print({successful_output()!r})"), 0)

    def test_fails_a_slow_test(self):
        self.assertEqual(self._run(5, f"print({successful_output(milliseconds=5001)!r})"), 1)

    def test_keeps_the_suite_exit_code(self):
        self.assertEqual(self._run(5, "import sys; sys.exit(3)"), 3)

    def test_real_child_temp_files_are_cleaned_on_every_outcome(self):
        with tempfile.TemporaryDirectory() as parent:
            marker = Path(parent) / 'root.txt'
            setup = (
                "import os,pathlib,time; "
                "root=os.environ['THREEMOJO_TEST_TMPDIR']; "
                "assert root == os.environ['TMPDIR']; "
                f"pathlib.Path({str(marker)!r}).write_text(root); "
                "pathlib.Path(root, 'fixture.bin').write_bytes(b'fixture'); ")
            for ending, seconds, expected in (
                    (f"print({successful_output()!r}); raise SystemExit(0)", 5, 0),
                    ("raise SystemExit(3)", 5, 3),
                    ("time.sleep(5)", 0.1, run_suite.TIMED_OUT)):
                self.assertEqual(self._run(seconds, setup + ending), expected)
                self.assertFalse(Path(marker.read_text()).exists())

    def test_empty_or_failed_zero_exit_process_cannot_pass(self):
        for program in ('pass', "print('    FAIL [ 1.0 ] test_a')"):
            self.assertEqual(self._run(5, program), 1)

    def test_complete_colored_results_are_required(self):
        self.assertEqual(run_suite.result_errors(successful_output()), [])
        self.assertEqual(run_suite.result_errors(
            successful_output().replace('PASS', '\x1b[92mPASS\x1b[0m')), [])
        self.assertTrue(run_suite.result_errors(OUTPUT))
        for broken in (
                '', 'Running 1 tests for suite.mojo',
                successful_output().split('Summary')[0],
                successful_output().replace('Running 1', 'Running 2'),
                '\n'.join(reversed(successful_output().splitlines())),
                successful_output().replace('1 passed', '0 passed'),
                successful_output().replace('1 tests run', '2 tests run'),
                successful_output().replace('    PASS [ 1.0 ] test_a\n', ''),
                successful_output() + '\n' + successful_output(),
                'Running 0 tests for suite.mojo\n'
                'Summary [ 0.0 ] 0 tests run: 0 passed , 0 failed , 0 skipped',
                successful_output().replace('PASS [ 1.0 ]', 'PASS [ nan ]')):
            with self.subTest(broken=broken):
                self.assertTrue(run_suite.result_errors(broken))

    def test_runtime_counts_can_include_imported_tests(self):
        output = ('Running 2 tests for suite.mojo\n'
                  'PASS [ 1.0 ] test_a\nPASS [ 2.0 ] test_imported\n'
                  'Summary [ 3.0 ] 2 tests run: 2 passed , 0 failed , 0 skipped')
        # _run's source defines one test; runtime evidence contains two.
        self.assertEqual(self._run(5, f'print({output!r})'), 0)

    def test_skips_and_device_notices_keep_their_separate_policy(self):
        skipped = ('Running 1 tests for suite.mojo\nSKIP [ 0.0 ] test_device\n'
                   'Summary [ 0.0 ] 1 tests run: 0 passed , 0 failed , 1 skipped')
        self.assertEqual(run_suite.result_errors(skipped), [])
        notice = 'SKIP (no accelerator): device test\n' + successful_output()
        self.assertEqual(run_suite.result_errors(notice), [])

    def test_stops_a_hung_suite(self):
        self.assertEqual(
            self._run(0.1, "import time; time.sleep(5)"), run_suite.TIMED_OUT)


if __name__ == "__main__":
    unittest.main()
