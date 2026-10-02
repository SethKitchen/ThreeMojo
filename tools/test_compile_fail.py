# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The negative-test harness must reject false passes and retain diagnostics."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import compile_fail


CRASHPAD_WARNING = (
    "Failed to initialize Crashpad.  Crash reporting will not be available.  "
    "Cause: while locating crashpad handler: unable to locate crashpad handler executable"
)


class DiagnosticTests(unittest.TestCase):
    fixture = "tests/compile_fail/fixture.mojo"

    def diagnostic(self, message="cannot implicitly convert 'Int' value to 'BodyId'"):
        return f"{self.fixture}:13:17: error: {message}\n"

    def test_semantic_rejection(self):
        self.assertIsNone(compile_fail.rejection_error(self.fixture, 1, self.diagnostic()))
        absolute = self.diagnostic().replace(self.fixture, str(Path(self.fixture).resolve()))
        self.assertIsNone(compile_fail.rejection_error(self.fixture, 1, absolute))
        self.assertIsNone(compile_fail.rejection_error(
            self.fixture, 1, '\x1b[31m' + self.diagnostic() + '\x1b[0m'))

    def test_compiled_fixture_fails(self):
        self.assertIn("compiled", compile_fail.rejection_error(self.fixture, 0, ""))

    def test_exact_crashpad_warning_with_expected_rejection(self):
        expected = {"errors": [{"line": 13, "column": 17,
                    "message": "cannot implicitly convert 'Int' value to 'BodyId'"}],
                    "notes": []}
        for newline in ("\n", "\r\n"):
            output = CRASHPAD_WARNING + newline + self.diagnostic()
            self.assertIsNone(compile_fail.rejection_error(
                self.fixture, 1, output, expected))
            self.assertIn("unexpected source", compile_fail.rejection_error(
                self.fixture, 1, output + self.diagnostic("unexpected token"), expected))

    def test_crashpad_warning_without_source_rejection_fails(self):
        self.assertIn("no located source error", compile_fail.rejection_error(
            self.fixture, 1, CRASHPAD_WARNING + "\n"))
        for code in (0, -11, 139):
            self.assertIsNotNone(compile_fail.rejection_error(
                self.fixture, code, CRASHPAD_WARNING + "\n" + self.diagnostic()))

    def test_crashpad_warning_does_not_hide_real_failures(self):
        for failure in ("LLVM ERROR: invalid IR", "segmentation fault", "stack dump",
                        "PLEASE submit a bug report", "internal compiler error",
                        "Assertion 'x != 0' failed", "out of memory",
                        "unable to locate module 'extensions'",
                        "failed to import module 'extensions'"):
            with self.subTest(failure=failure):
                self.assertIn("infrastructure", compile_fail.rejection_error(
                    self.fixture, 1, CRASHPAD_WARNING + "\n" + self.diagnostic() + failure))

    def test_only_exact_whole_crashpad_warning_line_is_allowed(self):
        for warning in ("prefix " + CRASHPAD_WARNING, CRASHPAD_WARNING + " suffix",
                        CRASHPAD_WARNING.replace("handler executable", "module 'extensions'"),
                        self.diagnostic(CRASHPAD_WARNING).rstrip("\n")):
            with self.subTest(warning=warning):
                self.assertIn("infrastructure", compile_fail.rejection_error(
                    self.fixture, 1, warning + "\n" + self.diagnostic()))

    def test_signal_timeout_and_shell_error_fail(self):
        for code in (-11, -9, 124, 126, 127, 137, 139):
            with self.subTest(code=code):
                self.assertIn("abnormally", compile_fail.rejection_error(
                    self.fixture, code, self.diagnostic()))

    def test_silent_and_driver_failures_fail(self):
        for output in ("", "mojo: error: compilation failed", "unknown argument: --wrong"):
            self.assertIsNotNone(compile_fail.rejection_error(self.fixture, 1, output))

    def test_import_failure_is_not_rejection(self):
        for message in ("unable to locate module 'extensions'", "cannot open file",
                        "could not find module", "No such file or directory"):
            with self.subTest(message=message):
                self.assertIn("infrastructure", compile_fail.rejection_error(
                    self.fixture, 1, self.diagnostic(message)))

    def test_dependency_error_is_not_rejection(self):
        output = self.diagnostic() + "units/length.mojo:3:1: error: broken declaration\n"
        self.assertIn("outside", compile_fail.rejection_error(self.fixture, 1, output))

    def test_crash_after_diagnostic_is_not_rejection(self):
        for suffix in ("LLVM ERROR: invalid IR", "PLEASE submit a bug report",
                       "Assertion 'x != 0' failed", "out of memory"):
            self.assertIn("infrastructure", compile_fail.rejection_error(
                self.fixture, 1, self.diagnostic() + suffix))

    def test_expected_message_and_location(self):
        expected = {"errors": [{"line": 13, "column": 17,
                     "message": "cannot implicitly convert 'Int' value to 'BodyId'"}], "notes": []}
        self.assertIsNone(compile_fail.rejection_error(
            self.fixture, 1, self.diagnostic(), expected))
        for output in (self.diagnostic("unexpected token"),
                       self.diagnostic().replace(':13:17:', ':14:17:'),
                       self.diagnostic() + self.diagnostic("unknown identifier")):
            self.assertIn("unexpected source", compile_fail.rejection_error(
                self.fixture, 1, output, expected))

    def test_candidate_notes_are_part_of_expected_reason(self):
        output = self.diagnostic("no matching function in initialization")
        output += "units/kind.mojo:7:2: note: value cannot be converted to BodyId\n"
        expected = {"errors": [{"line": 13, "column": 17,
            "message": "no matching function in initialization"}],
            "notes": ["value cannot be converted to BodyId"]}
        self.assertIsNone(compile_fail.rejection_error(self.fixture, 1, output, expected))
        drift = output.replace("value cannot be converted to BodyId",
                               "missing required argument: cast_shadow")
        self.assertIn("unexpected source", compile_fail.rejection_error(
            self.fixture, 1, drift, expected))

    def test_manifest_covers_exact_fixture_set(self):
        root = Path(__file__).resolve().parent.parent
        manifest = json.loads((root / 'tools/compile_fail_expectations.json').read_text())
        fixtures = {p.relative_to(root).as_posix()
                    for p in (root / 'tests/compile_fail').glob('*.mojo')}
        self.assertEqual(set(manifest), fixtures)
        for name, expected in manifest.items():
            lines = (root / name).read_text().splitlines()
            self.assertTrue(expected['errors'], name)
            for error in expected['errors']:
                self.assertTrue(1 <= error['line'] <= len(lines), name)
                self.assertGreater(error['column'], 0, name)
                self.assertTrue(error['message'], name)


class RunnerTests(unittest.TestCase):
    def run_main(self, fixture, results):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / 'expectations.json'
            manifest.write_text(json.dumps({fixture: {"errors": [
                {"line": 1, "column": 1, "message": "invalid conversion"}], "notes": []}}))
            with patch.object(compile_fail, 'compile_source', side_effect=results) as build:
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    with contextlib.redirect_stderr(output):
                        rc = compile_fail.main(['--compiler', 'mojo', '--flags=-I .',
                            '--expectations', str(manifest), fixture])
                return rc, output.getvalue(), build

    def test_control_prevents_broken_compiler_false_pass(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            result = subprocess.CompletedProcess([], 1, b'broken compiler')
            rc, output, build = self.run_main(fixture.name, [result])
            self.assertEqual(rc, 1)
            self.assertEqual(build.call_count, 1)
            self.assertIn('control failed', output)
            self.assertIn('broken compiler', output)

    def test_control_then_valid_rejection(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            results = [subprocess.CompletedProcess([], 0, b''),
                       subprocess.CompletedProcess([], 1,
                           f'{fixture.name}:1:1: error: invalid conversion\n'.encode())]
            rc, output, build = self.run_main(fixture.name, results)
            self.assertEqual(rc, 0)
            self.assertEqual(build.call_count, 2)
            self.assertIn('1 negative fixtures', output)
            self.assertFalse(build.call_args_list[0].args[2].exists())

    def test_failed_fixture_diagnostics_retained(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            results = [subprocess.CompletedProcess([], 0, b''),
                       subprocess.CompletedProcess([], 1, b'unknown argument --bad')]
            rc, output, _ = self.run_main(fixture.name, results)
            self.assertEqual(rc, 1)
            self.assertIn('unknown argument --bad', output)

    def test_control_with_crashpad_warning_still_requires_success(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            warning = (CRASHPAD_WARNING + '\n').encode()
            for code in (1, -11, 139):
                with self.subTest(code=code):
                    rc, output, build = self.run_main(fixture.name, [
                        subprocess.CompletedProcess([], code, warning)])
                    self.assertEqual(rc, 1)
                    self.assertEqual(build.call_count, 1)
                    self.assertIn('control failed', output)
                    self.assertIn(CRASHPAD_WARNING, output)
            rc, output, build = self.run_main(fixture.name, [
                subprocess.CompletedProcess([], 0, warning),
                subprocess.CompletedProcess([], 1, warning +
                    f'{fixture.name}:1:1: error: invalid conversion\n'.encode())])
            self.assertEqual(rc, 0)
            self.assertEqual(build.call_count, 2)

    def test_failed_fixture_retains_crashpad_warning_and_real_error(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            diagnostic = CRASHPAD_WARNING + '\nLLVM ERROR: invalid IR\n'
            rc, output, _ = self.run_main(fixture.name, [
                subprocess.CompletedProcess([], 0, b''),
                subprocess.CompletedProcess([], 1, diagnostic.encode())])
            self.assertEqual(rc, 1)
            self.assertIn(diagnostic, output)

    def test_launch_failure_and_timeout_fail(self):
        with tempfile.NamedTemporaryFile(suffix='.mojo') as fixture:
            for error in (FileNotFoundError('missing mojo'),
                          subprocess.TimeoutExpired('mojo', 120)):
                rc, output, _ = self.run_main(fixture.name, [error])
                self.assertEqual(rc, 1)
                self.assertIn('infrastructure error', output)

    def test_missing_fixture_fails_before_control(self):
        rc, output, build = self.run_main('/nonexistent/fixture.mojo', [])
        self.assertEqual(rc, 1)
        self.assertFalse(build.called)
        self.assertIn('infrastructure error', output)

    def test_empty_selection_needs_no_compiler(self):
        with patch.object(compile_fail, 'compile_source') as build:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(compile_fail.main(['--compiler', 'missing']), 0)
            self.assertFalse(build.called)

    def test_compile_arguments_and_timeout(self):
        with patch.object(subprocess, 'run') as run:
            compile_fail.compile_source(['mojo'], ['-I', '.'], Path('a.mojo'), 23)
            self.assertEqual(run.call_args.args[0],
                             ['mojo', 'build', '-I', '.', '-o', '/dev/null', 'a.mojo'])
            self.assertEqual(run.call_args.kwargs['timeout'], 23)


if __name__ == '__main__':
    unittest.main()
