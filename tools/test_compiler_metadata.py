# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Metadata-only and fake-command checks; no compiler work is executed."""

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import compiler_metadata as metadata

TARGET = ('Effective target configuration:\n'
          '  --target-triple x86_64-unknown-linux-gnu\n'
          '  --target-cpu x86-64-v3\n'
          '  --target-features +avx,+avx2,+fma\n')


class CompilerMetadataTests(unittest.TestCase):
    def test_selected_identity_target_and_no_compilation_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher, driver = root/'launcher', root/'driver'
            launcher.write_bytes(b'python launcher')
            driver.write_bytes(b'native driver')
            commands = []
            def run(command):
                commands.append(command)
                return ('Mojo 1.1.0 (8189361e)\n' if '--version' in command else TARGET), 'ok'
            result = metadata.collect(str(launcher), run, lambda: driver)
        self.assertEqual(result['driver']['sha256'], hashlib.sha256(b'native driver').hexdigest())
        self.assertNotEqual(result['driver']['sha256'], result['launcher']['sha256'])
        self.assertEqual(result['version'], 'Mojo 1.1.0 (8189361e)')
        self.assertEqual(result['effective_target']['target-features'], '+avx,+avx2,+fma')
        self.assertEqual(commands[1], [str(launcher), 'build', '--print-effective-target',
                                      *metadata.BUILD_ARGS])
        self.assertEqual(metadata.BUILD_ARGS, ['-I', '.', '--num-threads', '1',
                                             '--target-triple=x86_64-unknown-linux-gnu',
                                             '--target-cpu=x86-64-v3', '--Werror',
                                             '-o', '.cache/bin/test_exact_predicates',
                                             'tests/test_exact_predicates.mojo'])

    def test_unrecognized_output_and_environment_values_are_not_logged(self):
        token = 'DO_NOT_LOG_PRIVATE_ENV_VALUE'
        with patch.dict(os.environ, {'PRIVATE_TEST_VALUE': token}):
            result = metadata.collect('absent', lambda command: (token, 'ok'),
                                      lambda: (_ for _ in ()).throw(RuntimeError(token)))
        output = json.dumps(result)
        self.assertNotIn(token, output)
        self.assertEqual(result['version_status'], 'unrecognized-output')
        self.assertEqual(result['target_status'], 'unrecognized-output')
        self.assertEqual(result['driver']['status'], 'unavailable')

    def test_metadata_failure_does_not_replace_the_following_failure_gate(self):
        with patch.object(metadata, 'collect', side_effect=RuntimeError('private diagnostic')):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(metadata.main([]), 0)
        self.assertEqual(json.loads(output.getvalue())['status'], 'unavailable')
        self.assertNotIn('private diagnostic', output.getvalue())
        # The metadata-only command does not wrap or mask a later CPU command.
        result = subprocess.run(['sh', '-ec', '"$1" "$2" --compiler missing; exit 7', '_',
                                 sys.executable, str(Path(metadata.__file__))],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(result.returncode, 7)

    def test_whole_collector_deadline_covers_hashing_and_driver_resolution(self):
        for method in ('file_identity', 'active_driver'):
            with self.subTest(method=method):
                # collect's default resolver is bound at definition, so inject it.
                original = metadata.collect
                def collect(compiler):
                    if method == 'active_driver':
                        return original(compiler, resolve_driver=lambda: time.sleep(5))
                    return original(compiler)
                with patch.object(metadata, 'TOTAL_TIMEOUT', 0.03):
                    with patch.object(metadata, 'collect', side_effect=collect):
                        context = patch.object(metadata, 'file_identity', side_effect=lambda path: time.sleep(5)) if method == 'file_identity' else contextlib.nullcontext()
                        with context, contextlib.redirect_stdout(io.StringIO()) as output:
                            started = time.monotonic()
                            self.assertEqual(metadata.main([]), 0)
                self.assertLess(time.monotonic()-started, 2)
                self.assertEqual(json.loads(output.getvalue())['status'], 'unavailable')

    def test_other_launcher_cannot_be_labeled_with_this_interpreters_driver(self):
        with tempfile.NamedTemporaryFile() as stream:
            with patch.object(metadata.sys, 'executable', '/different/venv/bin/python'):
                with self.assertRaises((OSError, ValueError)):
                    metadata.active_driver(stream.name)
                result = metadata.collect(stream.name, lambda command: (None, 'unavailable'))
        self.assertEqual(result['driver']['status'], 'unavailable')

    def test_missing_metadata_command_is_unavailable(self):
        text, status = metadata.read_command(['/nonexistent/compiler-metadata-command'])
        self.assertIsNone(text)
        self.assertEqual(status, 'unavailable')

    def test_stderr_is_never_captured_or_emitted(self):
        text, status = metadata.read_command([sys.executable, '-c',
                                             'import sys; print("safe"); print("secret",file=sys.stderr)'])
        self.assertEqual((text, status), ('safe\n', 'ok'))

    def test_output_and_elapsed_time_have_small_bounds(self):
        text, status = metadata.read_command([sys.executable, '-c', 'print("x"*50000)'], limit=64)
        self.assertIsNone(text)
        self.assertEqual(status, 'output-limit')
        started = time.monotonic()
        text, status = metadata.read_command([sys.executable, '-c', 'import time; time.sleep(5)'], timeout=0.05)
        self.assertEqual((text, status), (None, 'timeout'))
        self.assertLess(time.monotonic()-started, 2)

    @unittest.skipUnless(sys.platform == 'linux' and Path('/proc/self/stat').is_file(),
                         'Linux procfs identity witness')
    def test_timeout_cleans_owned_descendant_that_holds_the_output_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / 'child.json'
            worker = ('import os,json,pathlib,time; '
                      'fields=pathlib.Path("/proc/self/stat").read_text().rpartition(")")[2].split(); '
                      f'pathlib.Path({str(receipt)!r}).write_text(json.dumps([os.getpid(),fields[19]])); '
                      'time.sleep(5)')
            code = ('import subprocess,sys,pathlib,time; '
                    f'subprocess.Popen([sys.executable,"-c",{worker!r}]); '
                    f'p=pathlib.Path({str(receipt)!r}); '
                    'exec("while not p.exists(): time.sleep(0.002)"); sys.exit(0)')
            started = time.monotonic()
            result = metadata.read_command([sys.executable, '-c', code], timeout=0.2)
            self.assertEqual(result, (None, 'timeout'))
            self.assertLess(time.monotonic()-started, 2)
            pid, original_start = json.loads(receipt.read_text())
            def still_running():
                try:
                    fields = Path(f'/proc/{pid}/stat').read_text().rpartition(')')[2].split()
                except FileNotFoundError:
                    return False
                return fields[19] == original_start and fields[0] != 'Z'
            try:
                deadline = time.monotonic() + 1
                while still_running() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertFalse(still_running(), 'owned descendant survived metadata timeout')
            finally:
                if still_running():
                    os.kill(pid, signal.SIGKILL)

    def test_binary_and_record_sizes_are_bounded(self):
        with tempfile.NamedTemporaryFile() as stream:
            stream.write(b'x'*20);stream.flush()
            with patch.object(metadata, 'MAX_BINARY', 10):
                self.assertEqual(metadata.file_identity(stream.name), {'status': 'unavailable'})
        with patch.object(metadata, 'collect', return_value={'oversize': 'x'*metadata.MAX_OUTPUT}):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(metadata.main([]), 0)
        self.assertLessEqual(len(output.getvalue().encode()), metadata.MAX_OUTPUT)
        self.assertEqual(json.loads(output.getvalue())['status'], 'record-limit')

    def test_targets_with_paths_duplicates_or_extra_text_are_not_logged(self):
        for extra in ('  --target-cpu secret\n', 'environment SECRET=private\n',
                      '  --target-features /private/path\n'):
            result = metadata.collect('absent', lambda command: (TARGET+extra, 'ok'), lambda: None)
            self.assertNotIn('effective_target', result)
            self.assertEqual(result['target_status'], 'unrecognized-output')


if __name__ == '__main__':
    unittest.main()
