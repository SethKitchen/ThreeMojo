# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The negative-test harness must reject false passes and retain diagnostics."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import shlex
import sys
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


class RegenerationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.fixtures = [str(self.root / (name + '.mojo')) for name in ('a', 'b', 'c')]
        for fixture in self.fixtures:
            Path(fixture).write_text('def main():\n    pass\n')
        self.manifest = self.root / 'expectations.json'
        self.expected = {'errors': [{'line': 1, 'column': 1,
                                    'message': 'old conversion'}], 'notes': []}
        self.records = {fixture: self.expected for fixture in self.fixtures}
        # Keep noncanonical bytes so refusals must preserve the file exactly.
        self.original = json.dumps(self.records).encode()
        self.manifest.write_bytes(self.original)

    def result(self, code=0, output=''):
        return subprocess.CompletedProcess([], code, output.encode())

    def rejection(self, fixture, message='new conversion', notes=''):
        return self.result(1, f'{fixture}:2:5: error: {message}\n' + notes)

    def run_main(self, fixtures, results, update=True):
        arguments = ['--compiler', 'mojo', '--flags=-I . --Werror',
                     '--expectations', str(self.manifest)]
        if update:
            arguments.append('--update-expectations')
        with patch.object(compile_fail, 'compile_source', side_effect=results) as build:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                with contextlib.redirect_stderr(output):
                    rc = compile_fail.main(arguments + fixtures)
        return rc, output.getvalue(), build

    def assert_untouched(self):
        self.assertEqual(self.manifest.read_bytes(), self.original)
        self.assertEqual(list(self.root.glob('expectations.json.*.tmp')), [])

    def test_subset_updates_exact_errors_and_notes_and_preserves_other_records(self):
        selected = self.fixtures[1]
        self.original = (json.dumps(self.records, indent=2) + '\n').encode()
        self.manifest.write_bytes(self.original)
        notes = "library.mojo:10:2: note: candidate needs BodyId\n"
        rc, output, build = self.run_main([selected], [
            self.result(), self.rejection(selected, notes=notes)])
        self.assertEqual(rc, 0, output)
        actual = json.loads(self.manifest.read_bytes())
        self.assertEqual(actual[selected], {
            'errors': [{'line': 2, 'column': 5, 'message': 'new conversion'}],
            'notes': ['candidate needs BodyId']})
        for fixture in (self.fixtures[0], self.fixtures[2]):
            self.assertEqual(actual[fixture], self.records[fixture])
        self.assertEqual(build.call_count, 2)
        self.assertEqual(build.call_args_list[1].args[2], selected)
        self.assertIn('--- ', output)
        self.assertIn('+++ ', output)
        self.assertIn('-        "message": "old conversion"', output)
        self.assertIn('+        "message": "new conversion"', output)
        self.assertIn('review every diagnostic change', output)

    def test_new_selected_fixture_can_be_added_without_dropping_records(self):
        selected = str(self.root / 'new.mojo')
        Path(selected).write_text('def main():\n    pass\n')
        rc, output, _ = self.run_main([selected], [self.result(), self.rejection(selected)])
        self.assertEqual(rc, 0, output)
        actual = json.loads(self.manifest.read_bytes())
        self.assertEqual(set(actual), set(self.records) | {selected})
        for fixture, record in self.records.items():
            self.assertEqual(actual[fixture], record)

    def test_output_is_stable_across_selection_order_color_and_duplicate_diagnostics(self):
        a, b, _ = self.fixtures
        diagnostic = (f'{a}:2:8: error: second\n'
                      f'{a}:2:5: error: first\n'
                      'library.mojo:4:1: note: z candidate\n'
                      'library.mojo:3:1: note: a candidate\n')
        rc, output, build = self.run_main([b, a, a], [self.result(),
            self.result(1, '\x1b[31m' + diagnostic + diagnostic + '\x1b[0m'),
            self.rejection(b)])
        self.assertEqual(rc, 0, output)
        self.assertEqual(build.call_count, 3)
        first = self.manifest.read_bytes()
        before = self.manifest.stat()
        reverse = '\n'.join(reversed(diagnostic.splitlines())) + '\n'
        with patch.object(compile_fail.os, 'replace') as replace:
            rc, output, _ = self.run_main([a, b], [self.result(),
                self.result(1, CRASHPAD_WARNING + '\n' + reverse), self.rejection(b)])
        self.assertEqual(rc, 0, output)
        self.assertFalse(replace.called)
        self.assertIn('unchanged', output)
        self.assertEqual(self.manifest.read_bytes(), first)
        self.assertEqual(self.manifest.stat().st_mtime_ns, before.st_mtime_ns)
        actual = json.loads(first)
        self.assertEqual(list(actual), sorted(actual))
        self.assertEqual([error['column'] for error in actual[a]['errors']], [5, 8])
        self.assertEqual(actual[a]['notes'], ['a candidate', 'z candidate'])

    def test_empty_update_selection_is_refused_before_compilation(self):
        with patch.object(compile_fail, 'compile_source') as build:
            with contextlib.redirect_stderr(io.StringIO()) as output:
                with self.assertRaises(SystemExit) as error:
                    compile_fail.main(['--compiler', 'mojo', '--update-expectations',
                                       '--expectations', str(self.manifest)])
        self.assertEqual(error.exception.code, 2)
        self.assertIn('explicit fixture', output.getvalue())
        self.assertFalse(build.called)
        self.assert_untouched()

    def test_failed_control_refuses_update(self):
        for code in (1, -11, 127):
            with self.subTest(code=code):
                rc, output, build = self.run_main(self.fixtures[:1], [
                    self.result(code, 'failed control')])
                self.assertEqual(rc, 1)
                self.assertEqual(build.call_count, 1)
                self.assertIn('control failed', output)
                self.assert_untouched()

    def test_invalid_selected_result_never_partially_updates(self):
        a, b, _ = self.fixtures
        valid = f'{b}:2:5: error: invalid conversion\n'
        refusals = [
            self.result(0, ''), self.result(0, valid),
            self.result(-11, valid), self.result(139, valid),
            self.result(1, ''), self.result(1, 'mojo: error: compilation failed'),
            self.result(1, CRASHPAD_WARNING + '\n'),
            self.result(1, valid + 'LLVM ERROR: invalid IR'),
            self.result(1, valid + 'internal compiler error'),
            self.result(1, valid + 'PLEASE submit a bug report'),
            self.result(1, valid + 'stack dump'),
            self.result(1, valid + "Assertion 'x' failed"),
            self.result(1, valid + 'out of memory'),
            self.result(1, valid + 'unknown argument: --wrong'),
            self.rejection(b, "unable to locate module 'missing'"),
            self.rejection(b, 'could not find module'),
            self.rejection(b, "failed to import module 'missing'"),
            self.result(1, valid + 'dependency.mojo:1:1: error: broken dependency\n'),
            self.result(1, valid + CRASHPAD_WARNING + ' suffix'),
        ]
        for result in refusals:
            with self.subTest(code=result.returncode, output=result.stdout):
                with patch.object(compile_fail, '_write_expectations') as write:
                    rc, output, build = self.run_main([a, b], [
                        self.result(), self.rejection(a), result])
                self.assertEqual(rc, 1, output)
                self.assertEqual(build.call_count, 3)
                self.assertFalse(write.called)
                self.assert_untouched()

    def test_launch_error_or_timeout_after_a_valid_result_cannot_write(self):
        a, b, _ = self.fixtures
        for error in (OSError('compiler unavailable'),
                      subprocess.TimeoutExpired('mojo', 120)):
            with self.subTest(error=error):
                rc, output, _ = self.run_main([a, b], [
                    self.result(), self.rejection(a), error])
                self.assertEqual(rc, 1)
                self.assertIn('infrastructure error', output)
                self.assert_untouched()

    def test_every_selected_file_must_exist_before_control(self):
        rc, output, build = self.run_main(self.fixtures + [str(self.root / 'missing.mojo')], [])
        self.assertEqual(rc, 1)
        self.assertIn('infrastructure error', output)
        self.assertFalse(build.called)
        self.assert_untouched()

    def test_invalid_manifest_is_refused_before_control(self):
        for content in (b'{', b'[]', b'null', '{}'.encode('utf-16')):
            with self.subTest(content=content):
                self.manifest.write_bytes(content)
                rc, output, build = self.run_main(self.fixtures[:1], [])
                self.assertEqual(rc, 1)
                self.assertIn('infrastructure error', output)
                self.assertFalse(build.called)
                self.assertEqual(self.manifest.read_bytes(), content)

    def test_normal_check_is_read_only_on_match_and_drift(self):
        a = self.fixtures[0]
        for message, expected_rc in [('old conversion', 0), ('new conversion', 1)]:
            with self.subTest(message=message):
                with patch.object(compile_fail, '_write_expectations') as write:
                    rc, output, _ = self.run_main([a], [self.result(), self.result(
                        1, f'{a}:1:1: error: {message}\n')], update=False)
                self.assertEqual(rc, expected_rc, output)
                self.assertFalse(write.called)
                self.assert_untouched()

    def test_normal_check_requires_an_existing_record(self):
        self.manifest.write_text('{}')
        rc, output, build = self.run_main(self.fixtures[:1], [], update=False)
        self.assertEqual(rc, 1)
        self.assertIn('Missing expected diagnostics', output)
        self.assertFalse(build.called)
        self.assertEqual(self.manifest.read_text(), '{}')

    def test_replace_happens_once_after_all_results_with_complete_json_and_same_mode(self):
        a, b, _ = self.fixtures
        self.manifest.chmod(0o640)
        original_replace = compile_fail.os.replace
        calls = []

        def replace(source, target):
            self.assertEqual(target, self.manifest)
            self.assertEqual(Path(source).parent, self.manifest.parent)
            self.assertEqual(self.manifest.read_bytes(), self.original)
            updated = json.loads(Path(source).read_bytes())
            for fixture in (a, b):
                self.assertEqual(updated[fixture]['errors'][0]['message'], 'new conversion')
            self.assertEqual(Path(source).stat().st_mode & 0o777, 0o640)
            calls.append(source)
            original_replace(source, target)

        with patch.object(compile_fail.os, 'replace', side_effect=replace):
            rc, output, _ = self.run_main([a, b], [
                self.result(), self.rejection(a), self.rejection(b)])
        self.assertEqual(rc, 0, output)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.manifest.stat().st_mode & 0o777, 0o640)
        self.assertEqual(list(self.root.glob('expectations.json.*.tmp')), [])

    def test_failed_flush_or_replace_preserves_original_and_removes_temporary_file(self):
        for operation in ('fsync', 'replace'):
            with self.subTest(operation=operation):
                with patch.object(compile_fail.os, operation, side_effect=OSError('disk failure')):
                    rc, output, _ = self.run_main(self.fixtures[:1], [
                        self.result(), self.rejection(self.fixtures[0])])
                self.assertEqual(rc, 1)
                self.assertIn('disk failure', output)
                self.assert_untouched()

    def test_concurrent_edit_is_not_overwritten(self):
        a = self.fixtures[0]
        concurrent = self.original + b'\n'

        def compile_source(command, flags, source, timeout):
            if str(source) == a:
                self.manifest.write_bytes(concurrent)
                return self.rejection(a)
            return self.result()

        rc, output, _ = self.run_main([a], compile_source)
        self.assertEqual(rc, 1)
        self.assertIn('changed during compilation', output)
        self.assertEqual(self.manifest.read_bytes(), concurrent)
        self.assertEqual(list(self.root.glob('expectations.json.*.tmp')), [])

    def test_update_refuses_symlink_but_read_only_check_can_follow_it(self):
        target = self.root / 'linked-expectations.json'
        self.manifest.rename(target)
        self.manifest.symlink_to(target.name)
        rc, output, build = self.run_main(self.fixtures[:1], [])
        self.assertEqual(rc, 1)
        self.assertIn('symlink', output)
        self.assertFalse(build.called)
        self.assertTrue(self.manifest.is_symlink())
        self.assertEqual(target.read_bytes(), self.original)
        a = self.fixtures[0]
        rc, output, _ = self.run_main([a], [self.result(), self.result(
            1, f'{a}:1:1: error: old conversion\n')], update=False)
        self.assertEqual(rc, 0, output)
        self.assertTrue(self.manifest.is_symlink())
        self.assert_untouched()

    def test_destination_swapped_to_symlink_during_write_is_not_replaced(self):
        target = self.root / 'linked-expectations.json'
        original_fsync = compile_fail.os.fsync

        def swap_to_symlink(fd):
            original_fsync(fd)
            self.manifest.rename(target)
            self.manifest.symlink_to(target.name)

        with patch.object(compile_fail.os, 'fsync', side_effect=swap_to_symlink):
            rc, output, _ = self.run_main(self.fixtures[:1], [
                self.result(), self.rejection(self.fixtures[0])])
        self.assertEqual(rc, 1)
        self.assertIn('symlink', output)
        self.assertTrue(self.manifest.is_symlink())
        self.assertEqual(target.read_bytes(), self.original)
        self.assert_untouched()

    def test_cli_regeneration_then_read_only_check_through_real_subprocess(self):
        compiler = self.root / 'compiler.py'
        compiler.write_text(
            'import pathlib, sys\n'
            'source = pathlib.Path(sys.argv[-1])\n'
            'if source.name == "control.mojo":\n'
            '    sys.exit(0)\n'
            'print(str(source) + ":2:5: error: invalid conversion")\n'
            'print("dependency.mojo:1:1: note: needs a typed value")\n'
            'sys.exit(1)\n')
        command = [sys.executable, str(Path(compile_fail.__file__).resolve()),
                   '--compiler', shlex.join([sys.executable, str(compiler)]),
                   '--flags=-I . --Werror', '--expectations', str(self.manifest),
                   self.fixtures[0]]
        generated = subprocess.run(command + ['--update-expectations'], capture_output=True,
                                   text=True, timeout=5)
        self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
        self.assertIn('needs a typed value', generated.stdout)
        before = self.manifest.read_bytes()
        checked = subprocess.run(command, capture_output=True, text=True, timeout=5)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertEqual(self.manifest.read_bytes(), before)

    def test_make_and_ci_never_request_regeneration(self):
        root = Path(compile_fail.__file__).resolve().parent.parent
        paths = [root / 'Makefile'] + list((root / '.github/workflows').glob('*.yml'))
        for path in paths:
            with self.subTest(path=path):
                self.assertNotIn('--update-expectations', path.read_text())


if __name__ == '__main__':
    unittest.main()
