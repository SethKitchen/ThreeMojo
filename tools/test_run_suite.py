# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for the time limit on each test of a suite."""

import os
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
        self.assertEqual(self._run(5, "print('    PASS [ 1.0 ] test_a')"), 0)

    def test_fails_a_slow_test(self):
        self.assertEqual(self._run(5, "print('    PASS [ 5001.0 ] test_a')"), 1)

    def test_keeps_the_suite_exit_code(self):
        self.assertEqual(self._run(5, "import sys; sys.exit(3)"), 3)

    def test_stops_a_hung_suite(self):
        self.assertEqual(
            self._run(0.1, "import time; time.sleep(5)"), run_suite.TIMED_OUT)


if __name__ == "__main__":
    unittest.main()
