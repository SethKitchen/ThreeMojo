# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep native fault qualification explicit and fail closed on bad receipts."""
import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

import coverage_hit_faults as faults


class TransportFaultDriver(unittest.TestCase):
    def invoke(self, arguments, outcomes):
        with patch('sys.argv', ['coverage_hit_faults.py', *arguments]), \
             patch.object(faults.subprocess, 'run', side_effect=outcomes) as run, \
             contextlib.redirect_stdout(io.StringIO()) as output:
            status = 0
            try:
                faults.main()
            except SystemExit as error:
                status = error.code
        return status, json.loads(output.getvalue()), run

    def test_default_remains_compiler_free_and_discloses_unrun_native_checks(self):
        status, receipt, run = self.invoke([], [])
        self.assertEqual(status, 0)
        self.assertEqual(receipt['native_harness'], 'not compiled or run')
        self.assertTrue(receipt['source_unchanged'])
        run.assert_not_called()

    def test_failed_compilation_never_runs_or_reports_a_native_pass(self):
        status, receipt, run = self.invoke(['--compile-run'], [
            SimpleNamespace(returncode=42, stdout='', stderr='original compiler error')])
        self.assertEqual(status, 1)
        self.assertEqual(receipt['native_harness'], 'compile failed')
        self.assertEqual(receipt['compile_stderr'], 'original compiler error')
        self.assertEqual(run.call_count, 1)

    def test_failed_native_control_is_preserved_and_returns_failure(self):
        status, receipt, run = self.invoke(['--compile-run'], [
            SimpleNamespace(returncode=0, stdout='', stderr=''),
            SimpleNamespace(returncode=-6, stdout='prior evidence', stderr='failed assertion')])
        self.assertEqual(status, 1)
        self.assertEqual(receipt['native_harness'], 'failed')
        self.assertEqual(receipt['run_returncode'], -6)
        self.assertEqual(receipt['run_stderr'], 'failed assertion')
        self.assertEqual(run.call_args_list[1].kwargs['timeout'], 5)

    def test_success_keeps_exact_source_harness_and_command_receipts(self):
        status, receipt, run = self.invoke(['--compile-run'], [
            SimpleNamespace(returncode=0, stdout='', stderr=''),
            SimpleNamespace(returncode=0, stdout='PASS41', stderr='')])
        self.assertEqual(status, 0)
        self.assertEqual(receipt['native_harness'], 'passed')
        self.assertEqual(receipt['run_stdout'], 'PASS41')
        self.assertEqual(len(receipt['source_sha256']), 64)
        self.assertEqual(len(receipt['harness_sha256']), 64)
        self.assertIn('-Werror', receipt['compile_command'])
        self.assertTrue(receipt['source_unchanged'])

    def test_source_drift_cannot_be_certified(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'helper.c'
            original = Path(faults.__file__).with_name('coverage_hit_cache.c')
            source.write_bytes(original.read_bytes())
            def changed(_command, **_kwargs):
                source.write_bytes(source.read_bytes()+b'\n/* changed */\n')
                return SimpleNamespace(returncode=0, stdout='', stderr='')
            with patch('sys.argv', ['coverage_hit_faults.py', '--compile-run', '--source', str(source)]), \
                 patch.object(faults.subprocess, 'run', side_effect=changed), \
                 contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(RuntimeError):
                    faults.main()


if __name__ == '__main__':
    unittest.main()
