# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Metadata-only and fake-command checks; no compiler work is executed."""

import contextlib
import errno
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, call, patch

import compiler_metadata as metadata

TARGET = ('Effective target configuration:\n'
          '  --target-triple x86_64-unknown-linux-gnu\n'
          '  --target-cpu x86-64-v3\n'
          '  --target-features +avx,+avx2,+fma\n')


def _owned_descendant_running(pid, original_start):
    if pid is None:
        return False
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rpartition(')')[2].split()
    except (FileNotFoundError, ProcessLookupError):
        # The process can be reaped after open() but before read().
        return False
    return fields[19] == original_start and fields[0] != 'Z'


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

    def cleanup_denial(self, *, live=False, probe=None, platform='darwin', number=errno.EPERM,
                       wait_error=None):
        child = Mock(pid=12345, returncode=None, stdout=io.BytesIO())
        events = []
        denied = PermissionError(number, 'initial denial')

        def wait(timeout=None):
            events.append(('wait', timeout))
            self.assertIsNotNone(timeout, 'cleanup waits must stay bounded')
            if wait_error is not None:
                raise wait_error
            if live:
                raise subprocess.TimeoutExpired('owned', timeout)
            child.returncode = 0
            return 0

        def killpg(pid, signal_number):
            events.append(('signal', signal_number))
            self.assertEqual(pid, child.pid)
            if signal_number == signal.SIGKILL:
                self.assertIsNone(child.returncode, 'never signal after reaping')
                raise denied
            self.assertEqual(signal_number, 0)
            self.assertEqual(child.returncode, 0, 'probe must follow reaping')
            if probe is not None:
                raise probe

        child.wait.side_effect = wait
        with patch.object(metadata.subprocess, 'Popen', return_value=child), \
                patch.object(metadata.selectors, 'DefaultSelector'), \
                patch.object(metadata.sys, 'platform', platform), \
                patch.object(metadata.os, 'killpg', side_effect=killpg):
            if not live and platform == 'darwin' and number == errno.EPERM and isinstance(probe, ProcessLookupError):
                self.assertEqual(metadata.read_command(['owned'], timeout=0), (None, 'timeout'))
            else:
                expected = wait_error or probe or denied
                with self.assertRaises(type(expected)) as raised:
                    metadata.read_command(['owned'], timeout=0)
                self.assertIs(raised.exception, expected)
        self.assertTrue(child.stdout.closed, 'failure must also close the local pipe')
        return child, events

    def test_darwin_eperm_with_live_leader_fails_without_unbounded_wait(self):
        child, events = self.cleanup_denial(live=True)
        self.assertIsNone(child.returncode)
        self.assertEqual(events, [('signal', signal.SIGKILL), ('wait', 0)])

    def test_reaped_leader_with_present_or_denied_group_fails(self):
        for probe in (None, PermissionError(errno.EPERM, 'probe denied'),
                      OSError(errno.EIO, 'probe failed'), KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(probe=probe):
                child, events = self.cleanup_denial(probe=probe)
                self.assertEqual(child.returncode, 0)
                self.assertEqual(events, [('signal', signal.SIGKILL), ('wait', 0), ('signal', 0)])

    def test_unexpected_reap_failure_propagates_without_another_wait_or_signal(self):
        for error in (OSError(errno.ECHILD, 'wait failed'), KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(error=error):
                child, events = self.cleanup_denial(wait_error=error)
                self.assertIsNone(child.returncode)
                self.assertEqual(events, [('signal', signal.SIGKILL), ('wait', 0)])

    def test_reaped_leader_with_absent_group_preserves_timeout_without_more_signals(self):
        child, events = self.cleanup_denial(probe=ProcessLookupError(errno.ESRCH, 'gone'))
        self.assertEqual(child.returncode, 0)
        self.assertEqual(events, [('signal', signal.SIGKILL), ('wait', 0), ('signal', 0), ('wait', 0)])

    def test_unrelated_platform_and_permission_errors_are_not_reclassified(self):
        for platform, number in (('linux', errno.EPERM), ('darwin', errno.EACCES)):
            with self.subTest(platform=platform, errno=number):
                child, events = self.cleanup_denial(platform=platform, number=number)
                self.assertIsNone(child.returncode)
                self.assertEqual(events, [('signal', signal.SIGKILL)])

    def test_managed_signals_defer_across_reap_even_from_another_thread(self):
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGALRM):
            for already_exited in (False, True):
                with self.subTest(signal=number, reaped=already_exited):
                    child = Mock(pid=12345, returncode=None, stdout=io.BytesIO())
                    first = True
                    old_handlers = {n: signal.getsignal(n) for n in
                                    (signal.SIGTERM, signal.SIGINT, signal.SIGALRM)}
                    old_timer = signal.getitimer(signal.ITIMER_REAL)
                    old_guard = getattr(metadata._REAP_STATE, 'guard', None)

                    def wait(timeout):
                        nonlocal first
                        self.assertEqual(timeout, 0)
                        if first:
                            first = False
                            if already_exited:
                                child.returncode = 0
                            sender = threading.Thread(target=lambda: os.kill(os.getpid(), number))
                            sender.start()
                            sender.join(timeout=1)
                            self.assertFalse(sender.is_alive())
                            # A Python callback ran on main despite delivery
                            # from another thread, and must have been deferred.
                            self.assertIsNotNone(metadata._REAP_STATE.guard.pending)
                            if not already_exited:
                                raise subprocess.TimeoutExpired('owned', 0)
                        else:
                            child.returncode = -signal.SIGKILL
                        return child.returncode

                    def collect(_compiler):
                        metadata.read_command(['owned'], timeout=0.2)
                        self.fail('managed signal was not replayed')

                    def killpg(pid, signum):
                        self.assertEqual((pid, signum), (child.pid, signal.SIGKILL))
                        self.assertIsNone(child.returncode, 'destructive signal after reaping')

                    child.wait.side_effect = wait
                    with patch.object(metadata.subprocess, 'Popen', return_value=child), \
                            patch.object(metadata.selectors, 'DefaultSelector') as selector, \
                            patch.object(metadata, 'collect', side_effect=collect), \
                            patch.object(metadata.os, 'killpg', side_effect=killpg) as kill, \
                            contextlib.redirect_stdout(io.StringIO()) as output:
                        selector.return_value.__enter__.return_value.get_map.return_value = {}
                        if number == signal.SIGALRM:
                            self.assertEqual(metadata.main([]), 0)
                            self.assertEqual(json.loads(output.getvalue())['status'], 'unavailable')
                        else:
                            with self.assertRaises(SystemExit) as raised:
                                metadata.main([])
                            self.assertEqual(raised.exception.code, 128 + number)
                    self.assertEqual(kill.call_count, 0 if already_exited else 1)
                    self.assertEqual(child.wait.call_count, 1 if already_exited else 2)
                    self.assertTrue(child.stdout.closed)
                    self.assertEqual({n: signal.getsignal(n) for n in old_handlers}, old_handlers)
                    self.assertEqual(signal.getitimer(signal.ITIMER_REAL), old_timer)
                    self.assertIs(getattr(metadata._REAP_STATE, 'guard', None), old_guard)

    def test_normal_wait_unexpected_errors_are_not_swallowed_as_unavailable(self):
        for error in (OSError(errno.ECHILD, 'uncertain reap'), KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(error=error):
                child = Mock(pid=12345, returncode=None, stdout=io.BytesIO())
                child.wait.side_effect = error
                with patch.object(metadata.subprocess, 'Popen', return_value=child), \
                        patch.object(metadata.selectors, 'DefaultSelector') as selector, \
                        patch.object(metadata.os, 'killpg') as kill, \
                        self.assertRaises(type(error)) as raised:
                    selector.return_value.__enter__.return_value.get_map.return_value = {}
                    metadata.read_command(['owned'], timeout=0.2)
                self.assertIs(raised.exception, error)
                kill.assert_not_called()
                child.wait.assert_called_once_with(timeout=0)
                self.assertTrue(child.stdout.closed)

    def test_worker_thread_read_does_not_borrow_main_thread_signal_guard(self):
        result, guards = [], []
        old_guard = getattr(metadata._REAP_STATE, 'guard', None)
        main_guard = metadata._ReapGuard()
        main_guard.active = True
        metadata._REAP_STATE.guard = main_guard
        def worker():
            guards.append(getattr(metadata._REAP_STATE, 'guard', None))
            result.append(metadata.read_command([sys.executable, '-c', 'print("worker")']))
        thread = threading.Thread(target=worker)
        try:
            thread.start()
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(guards, [None])
            self.assertEqual(result, [('worker\n', 'ok')])
            self.assertTrue(main_guard.active)
            self.assertIsNone(main_guard.pending)
        finally:
            metadata._REAP_STATE.guard = old_guard

    def test_managed_cancellation_reaps_a_real_live_child_after_stdout_closes(self):
        real_popen = subprocess.Popen
        child = None
        def spawn(*args, **kwargs):
            nonlocal child
            child = real_popen(*args, **kwargs)
            real_wait = child.wait
            first = True
            def wait(timeout=None):
                nonlocal first
                if first:
                    first = False
                    signal.raise_signal(signal.SIGTERM)
                    self.assertIsNotNone(metadata._REAP_STATE.guard.pending)
                return real_wait(timeout=timeout)
            child.wait = wait
            return child
        def collect(_compiler):
            metadata.read_command([sys.executable, '-c', 'import os,time;os.close(1);time.sleep(5)'])
            self.fail('cancellation was lost')
        try:
            with patch.object(metadata.subprocess, 'Popen', side_effect=spawn), \
                    patch.object(metadata, 'collect', side_effect=collect), \
                    self.assertRaises(SystemExit) as raised:
                metadata.main([])
            self.assertEqual(raised.exception.code, 143)
            self.assertEqual(child.returncode, -signal.SIGKILL)
            self.assertTrue(child.stdout.closed)
        finally:
            if child is not None and child.returncode is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=1)
                child.stdout.close()

    def test_owned_descendant_running_accepts_reaped_process(self):
        for error in (FileNotFoundError(errno.ENOENT, 'gone'),
                      ProcessLookupError(errno.ESRCH, 'gone')):
            with self.subTest(error=type(error).__name__), \
                    patch.object(Path, 'read_text', autospec=True, side_effect=error) as read:
                self.assertFalse(_owned_descendant_running(123, '456'))
                read.assert_called_once_with(Path('/proc/123/stat'))

    def test_owned_descendant_running_matches_live_identity(self):
        for state, start, expected in (('R', '456', True), ('S', '456', True),
                                       ('Z', '456', False), ('R', '789', False),
                                       ('S', '789', False), ('Z', '789', False)):
            fields = [state] + ['0'] * 18 + [start]
            stat = '123 (worker (descendant)) ' + ' '.join(fields)
            with self.subTest(state=state, start=start), \
                    patch.object(Path, 'read_text', autospec=True, return_value=stat) as read:
                self.assertEqual(_owned_descendant_running(123, '456'), expected)
                read.assert_called_once_with(Path('/proc/123/stat'))

    def test_owned_descendant_running_without_identity_skips_procfs(self):
        with patch.object(Path, 'read_text') as read:
            self.assertFalse(_owned_descendant_running(None, None))
        read.assert_not_called()

    def test_owned_descendant_running_propagates_unrelated_stat_errors(self):
        for error in (PermissionError(errno.EACCES, 'denied'),
                      PermissionError(errno.EPERM, 'denied'),
                      OSError(errno.EIO, 'read failed'),
                      OSError(errno.EINVAL, 'invalid read'),
                      NotADirectoryError(errno.ENOTDIR, 'not a directory')):
            with self.subTest(error=type(error).__name__, errno=error.errno), \
                    patch.object(Path, 'read_text', side_effect=error), \
                    self.assertRaises(type(error)) as raised:
                _owned_descendant_running(123, '456')
            self.assertIs(raised.exception, error)

    @unittest.skipUnless(sys.platform == 'linux' and Path('/proc/self/stat').is_file(),
                         'Linux procfs identity witness')
    def test_timeout_cleans_owned_descendant_that_holds_the_output_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / 'child.json'
            temporary = receipt.with_suffix('.tmp')
            partial_ready = Path(directory) / 'partial-ready'
            release = Path(directory) / 'release'
            worker = ('import os,json,pathlib,time; '
                      'fields=pathlib.Path("/proc/self/stat").read_text().rpartition(")")[2].split(); '
                      f'temporary=pathlib.Path({str(temporary)!r}); temporary.write_text(""); '
                      f'pathlib.Path({str(partial_ready)!r}).touch(); '
                      f'release=pathlib.Path({str(release)!r}); '
                      'exec("while not release.exists(): time.sleep(0.002)"); '
                      'temporary.write_text(json.dumps([os.getpid(),fields[19]])); '
                      f'temporary.replace({str(receipt)!r}); time.sleep(5)')
            code = ('import subprocess,sys,pathlib,time; '
                    f'subprocess.Popen([sys.executable,"-c",{worker!r}]); '
                    f'p=pathlib.Path({str(receipt)!r}); '
                    'exec("while not p.exists(): time.sleep(0.002)"); sys.exit(0)')
            real_popen = metadata.subprocess.Popen
            pid, original_start = None, None
            def ready_popen(*args, **kwargs):
                nonlocal pid, original_start
                # Fixture startup is separate from the unchanged 0.2-second
                # timeout under test. Force the formerly racy empty-file state
                # before allowing an atomic, complete identity publication.
                child = real_popen(*args, **kwargs)
                deadline = time.monotonic() + 1
                def wait_for(path):
                    while not path.exists():
                        if time.monotonic() >= deadline:
                            raise RuntimeError('metadata descendant fixture did not become ready')
                        time.sleep(0.002)
                try:
                    wait_for(partial_ready)
                    self.assertEqual(temporary.read_bytes(), b'')
                    self.assertFalse(receipt.exists())
                    release.touch()
                    wait_for(receipt)
                    identity = json.loads(receipt.read_text())
                    self.assertEqual(len(identity), 2)
                    pid, original_start = identity
                    return child
                except BaseException:
                    try:
                        try:
                            os.killpg(child.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        child.wait(timeout=1)
                    finally:
                        if child.stdout is not None:
                            child.stdout.close()
                    raise
            def still_running():
                return _owned_descendant_running(pid, original_start)
            started = time.monotonic()
            try:
                with patch.object(metadata.subprocess, 'Popen', side_effect=ready_popen):
                    result = metadata.read_command([sys.executable, '-c', code], timeout=0.2)
                self.assertEqual(result, (None, 'timeout'))
                self.assertLess(time.monotonic()-started, 2)
                pid, original_start = json.loads(receipt.read_text())
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
