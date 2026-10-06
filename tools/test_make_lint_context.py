# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check CPU lint failure context without invoking the Mojo compiler."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS'}
ENTRIES = ('examples/first.mojo', 'tools/second.mojo', 'tests/suite.mojo')
DOCS = ('math/first.mojo', 'render/second.mojo')
FLAGS = ['-I', '.', '-D', 'value with spaces; $literal']


class CpuLintContextTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='lint context ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in MAKE_ENVIRONMENT}
        self.environment['LINT_CONTEXT_PRIVATE_SENTINEL'] = 'must-not-be-printed'
        (self.root / 'compiler.py').write_text(
            'import json, os, sys\n'
            'from pathlib import Path\n'
            'argv = sys.argv[1:]\n'
            'fd = os.open("invocations", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)\n'
            'os.write(fd, (json.dumps(argv) + "\\n").encode())\n'
            'os.close(fd)\n'
            'config = json.loads(Path("config.json").read_text())\n'
            'if config.get("diagnostics"):\n'
            '    print("compiler stdout: " + argv[-1], flush=True)\n'
            '    print("Failed to initialize Crashpad", file=sys.stderr, flush=True)\n'
            '    print("compiler stderr: " + argv[-1], file=sys.stderr, flush=True)\n'
            'if argv[0] == config.get("operation") and argv[-1] == config.get("source"):\n'
            '    raise SystemExit(config["status"])\n')
        source = (ROOT / 'Makefile').read_text()
        start = source.index('lint-cpu: $(LINT_CPU_STAMP)\n')
        end = source.index('\n# Compile all maintained GPU', start)
        (self.root / 'Makefile').write_text(
            'JOBS := 3\nMOJO := python3 compiler.py\n'
            'MOJOFLAGS := -I . -D "value with spaces; \\$$literal"\n'
            'CPU_ENTRY_POINTS := ' + ' '.join(ENTRIES) + '\n'
            'CPU_TESTS := tests/suite.mojo\n'
            'CPU_DOC_SOURCES := ' + ' '.join(DOCS) + '\n'
            'LINT_CPU_STAMP := lint-cpu-stamp\n'
            'stamp = touch $(1)-stamp\n' + source[start:end] + '\n')
        self.configure()

    def configure(self, **config):
        (self.root / 'config.json').write_text(json.dumps(config))

    def make(self, *arguments):
        return subprocess.run(['make', '-s', *arguments, 'lint-cpu'],
                              cwd=self.root, text=True, capture_output=True,
                              env=self.environment, timeout=5)

    def calls(self):
        log = self.root / 'invocations'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def wrapper(self, operation, source, *arguments):
        # Run the maintained shell wrapper directly: xargs and make intentionally
        # map a failed child's status, so only this boundary exposes the exact rc.
        preview = self.make('-n', *arguments)
        self.assertEqual(preview.returncode, 0, preview.stderr)
        tokens = shlex.split(preview.stdout)
        scripts = [tokens[index + 2] for index, token in enumerate(tokens)
                   if token == 'sh' and tokens[index + 1] == '-c']
        self.assertEqual(len(scripts), 2)
        return subprocess.run(['/bin/sh', '-c', scripts[operation == 'doc'], '_', source],
                              cwd=self.root, text=True, capture_output=True,
                              env=self.environment, timeout=5)

    def expected_diagnostics(self, source):
        # GNU and BSD sed differ on an unterminated final line. Use the host's
        # unchanged filter to retain the original wrapper's byte behavior.
        return subprocess.run(
            ['sed', '/Crashpad/d'], text=True, capture_output=True, check=True,
            input=(f'compiler stdout: {source}\nFailed to initialize Crashpad\n'
                   f'compiler stderr: {source}')).stdout

    def assert_context(self, result, operation, source, status):
        lines = result.stderr.splitlines()
        self.assertEqual(len(lines), 2, result.stderr)
        self.assertEqual(lines[0], f'lint-cpu failed: {source} (exit {status})')
        self.assertTrue(lines[1].startswith('command: '), result.stderr)
        argv = shlex.split(lines[1].removeprefix('command: '))
        self.assertEqual(argv, ['python3', 'compiler.py', operation, *FLAGS,
                                '--Werror', '-o', '/dev/null', source])
        self.assertNotIn('must-not-be-printed', result.stdout + result.stderr)
        self.assertNotIn('LINT_CONTEXT_PRIVATE_SENTINEL', result.stdout + result.stderr)

    def test_success_preserves_exact_selection_arguments_and_silence(self):
        result = self.make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected = [('build', path) for path in ENTRIES[:-1]] + [('doc', path) for path in DOCS]
        self.assertCountEqual(self.calls(), [
            [operation, *FLAGS, '--Werror', '-o', '/dev/null', path]
            for operation, path in expected])
        self.assertEqual(result.stdout, 'No warnings (CPU).\n')
        self.assertEqual(result.stderr, '')
        self.assertTrue((self.root / 'lint-cpu-stamp').exists())

    def test_target_override_is_build_only_and_default_doc_flags_are_preserved(self):
        target = ['--target-triple=x86_64-unknown-linux-gnu', '--target-cpu=x86-64-v3']
        result = self.make('LINT_CPU_BUILD_FLAGS=' + ' '.join(target))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertCountEqual(self.calls(), [
            ['build', *FLAGS, *target, '--Werror', '-o', '/dev/null', path]
            for path in ENTRIES[:-1]
        ] + [
            ['doc', *FLAGS, '--Werror', '-o', '/dev/null', path] for path in DOCS
        ])
        source = (ROOT / 'Makefile').read_text()
        self.assertIn('--setting=$(call quote,lint-cpu-build-flags:$(LINT_CPU_BUILD_FLAGS))', source)

    def test_progress_names_each_command_and_preserves_failure_status(self):
        for operation, source in (('build', ENTRIES[0]), ('doc', DOCS[0])):
            for status in (0, 7):
                with self.subTest(operation=operation, status=status):
                    self.configure(operation=operation, source=source, status=status)
                    result = self.wrapper(operation, source, 'LINT_CPU_PROGRESS=1')
                    self.assertEqual(result.returncode, status)
                    lines = result.stdout.splitlines()
                    self.assertEqual(len(lines), 2)
                    prefix = f' lint-{operation}-start: '
                    self.assertIn(prefix, lines[0])
                    self.assertEqual(shlex.split(lines[0].split(prefix, 1)[1]),
                                     ['python3', 'compiler.py', operation, *FLAGS,
                                      '--Werror', '-o', '/dev/null', source])
                    self.assertTrue(lines[1].endswith(
                        f' lint-{operation}-end: source={source} exit={status}'))
                    self.assertLessEqual(len(lines[0]), 4096)
                    self.assertNotIn('must-not-be-printed', result.stdout + result.stderr)
                    if status:
                        self.assert_context(result, operation, source, status)
                    else:
                        self.assertEqual(result.stderr, '')

    def test_each_wrapper_preserves_exact_failure_status_and_diagnostics(self):
        for operation, source in (('build', ENTRIES[0]), ('doc', DOCS[0])):
            for status in (1, 7, 139, 255):
                with self.subTest(operation=operation, status=status):
                    self.configure(operation=operation, source=source,
                                   status=status, diagnostics=True)
                    result = self.wrapper(operation, source)
                    self.assertEqual(result.returncode, status)
                    # The existing wrapper combines compiler stderr into stdout,
                    # strips Crashpad, and trims the final captured newline.
                    self.assertEqual(result.stdout,
                                     self.expected_diagnostics(source))
                    self.assert_context(result, operation, source, status)

    def test_each_wrapper_preserves_success_diagnostics_without_context(self):
        self.configure(diagnostics=True)
        for operation, source in (('build', ENTRIES[0]), ('doc', DOCS[0])):
            with self.subTest(operation=operation):
                result = self.wrapper(operation, source)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout,
                                 self.expected_diagnostics(source))
                self.assertEqual(result.stderr, '')

    def test_build_failure_keeps_all_entries_and_blocks_docs_and_stamp(self):
        self.configure(operation='build', source=ENTRIES[0], status=7)
        result = self.make()
        self.assertEqual(result.returncode, 2)
        self.assertCountEqual([call[-1] for call in self.calls()], ENTRIES[:-1])
        self.assertTrue(all(call[0] == 'build' for call in self.calls()))
        self.assertIn(f'lint-cpu failed: {ENTRIES[0]} (exit 7)', result.stderr)
        self.assertNotIn('No warnings', result.stdout)
        self.assertFalse((self.root / 'lint-cpu-stamp').exists())

    def test_doc_failure_keeps_all_selected_inputs_and_blocks_stamp(self):
        self.configure(operation='doc', source=DOCS[0], status=7)
        result = self.make()
        self.assertEqual(result.returncode, 2)
        self.assertCountEqual([call[-1] for call in self.calls()], [*ENTRIES[:-1], *DOCS])
        self.assertIn(f'lint-cpu failed: {DOCS[0]} (exit 7)', result.stderr)
        self.assertNotIn('No warnings', result.stdout)
        self.assertFalse((self.root / 'lint-cpu-stamp').exists())

    def test_success_cache_hit_and_force_rebuild(self):
        first = self.make()
        self.assertEqual(first.returncode, 0, first.stderr)
        calls = self.calls()
        cached = self.make()
        self.assertEqual(cached.returncode, 0, cached.stderr)
        self.assertEqual(cached.stdout + cached.stderr, '')
        self.assertEqual(self.calls(), calls)
        rebuilt = self.make('-B')
        self.assertEqual(rebuilt.returncode, 0, rebuilt.stderr)
        self.assertCountEqual(self.calls(), calls * 2)

    def test_parent_make_overrides_cannot_invoke_another_compiler(self):
        with patch.dict(os.environ, {
            'MAKEFLAGS': '-- MOJO=unavailable-outer-compiler',
            'MAKEOVERRIDES': 'MOJO=unavailable-outer-compiler',
            'MFLAGS': '-e', 'GNUMAKEFLAGS': '-e',
            'MAKEFILES': 'unavailable-outer-include', 'MAKELEVEL': '7',
        }):
            self.setUp()
            result = self.make()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(self.calls()), 4)


if __name__ == '__main__':
    unittest.main()
