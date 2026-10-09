# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free coverage deadline and descendant-cleanup controls."""

import contextlib
import errno
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, call, patch

import coverage_io


WORKER = '''import os, pathlib, signal, subprocess, sys, time
root = pathlib.Path(sys.argv[1])
role, mode = sys.argv[2:4]
signal.signal(signal.SIGTERM, signal.SIG_IGN)
(root / (role + '.pid')).write_text(str(os.getpid()))
if role == 'child':
    (root / 'temporary').write_text(os.environ['THREEMOJO_TEST_TMPDIR'])
    subprocess.Popen([sys.executable, __file__, str(root), 'grandchild', mode])
    while not (root / 'grandchild.pid').exists():
        time.sleep(0.01)
    if mode == 'malformed':
        sys.stderr.write('COVBRANCH:m:1.0:T\\n')
    else:
        sys.stderr.write('COVLINE:m:1\\n')
    sys.stderr.flush()
while True:
    time.sleep(0.02)
'''

DRIVER = '''import pathlib, sys
import coverage_io
root = pathlib.Path(sys.argv[1])
status = coverage_io.capture([sys.executable, str(root / 'worker.py'),
                             str(root), 'child', sys.argv[2]],
                            root / 'out', root / 'err.gz')
(root / 'status').write_text(str(status))
sys.exit(status)
'''

PREPARED_DRIVER = '''import contextlib, os, pathlib, signal, subprocess, sys, time
from unittest.mock import Mock, call, patch
import coverage_io
root = pathlib.Path(sys.argv[1])
parent = int(sys.argv[2]) if len(sys.argv) > 2 else os.getppid()
if os.getppid() != parent:
    raise RuntimeError('fixture parent exited before preparing capture')
command = [sys.executable, str(root / 'worker.py'), str(root), 'child', 'valid']
with contextlib.ExitStack() as scope:
    environment = scope.enter_context(coverage_io.isolated_environment())
    output = scope.enter_context(open(root / 'out', 'wb'))
    child = subprocess.Popen(command, stdout=output, stderr=subprocess.PIPE,
                             env=environment, start_new_session=True)
    try:
        owned = root / 'owned-child.tmp'
        owned.write_text(str(child.pid))
        owned.replace(root / 'owned-child.pid')
        while not (root / 'deadline').exists():
            if os.getppid() != parent:
                raise RuntimeError('fixture parent exited before releasing capture')
            time.sleep(0.01)
        os.environ[coverage_io.DEADLINE_ENV] = (root / 'deadline').read_text()

        @contextlib.contextmanager
        def prepared_environment():
            with scope:
                yield environment

        def adopt(*args, **kwargs):
            if (args != (command,) or kwargs['env'] is not environment
                    or kwargs['stderr'] != subprocess.PIPE
                    or kwargs['start_new_session'] is not True):
                raise AssertionError('capture did not adopt the prepared fixture')
            return child

        with patch.object(coverage_io.subprocess, 'Popen', side_effect=adopt) as spawn, \\
                patch.object(coverage_io, 'isolated_environment', prepared_environment):
            status = coverage_io.capture(command, root / 'out', root / 'err.gz')
        if spawn.call_count != 1:
            raise AssertionError('capture must adopt the fixture exactly once')
        if pathlib.Path(environment['THREEMOJO_TEST_TMPDIR']).exists():
            raise AssertionError('capture did not remove its temporary directory')
        (root / 'status').write_text(str(status))
    except BaseException:
        # A failed setup must kill the group before reaping its leader.
        if child.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=2)
        child.stderr.close()
        raise
sys.exit(status)
'''


class CoverageGroupCleanupTests(unittest.TestCase):
    def test_successful_group_signal_is_not_repeated_while_reaping(self):
        process = self.process()
        attempts = 0

        def wait(timeout):
            nonlocal attempts
            self.assertEqual(timeout, None if attempts == 4 else 0)
            self.assertFalse(process.active)
            attempts += 1
            # Same-thread callbacks can arrive during an owner-managed reap.
            process._signal(signal.SIGHUP, None)
            if attempts <= 3:
                raise subprocess.TimeoutExpired('owned', timeout)
            process.child.returncode = -signal.SIGKILL
            return process.child.returncode

        def killpg(pid, number):
            self.assertEqual((pid, number), (process.child.pid, signal.SIGKILL))
            self.assertTrue(process.active)
            self.assertIsNone(process.child.returncode)
            # Reentry before the syscall returns cannot start another kill.
            process._signal(signal.SIGTERM, None)

        process.child.wait.side_effect = wait
        with patch.object(coverage_io.os, 'killpg', side_effect=killpg) as kill:
            process.cancel(128 + signal.SIGINT)
            self.assertTrue(process.active, 'successful dispatch does not reap')
            self.assertEqual(process.wait(), 128 + signal.SIGINT)
            process.__exit__()
        kill.assert_called_once_with(process.child.pid, signal.SIGKILL)
        self.assertFalse(process.active)
        self.assertEqual(attempts, 5)
        self.assertTrue(process.child.stderr.closed)

    def test_successful_group_signal_still_reaps_on_exit(self):
        process = self.process()
        with patch.object(coverage_io.os, 'killpg') as kill:
            process.cancel(124)
            process._kill()
            process.__exit__()
        kill.assert_called_once_with(process.child.pid, signal.SIGKILL)
        process.child.wait.assert_called_once_with(timeout=None)
        self.assertFalse(process.active)
        self.assertTrue(process.child.stderr.closed)

    def test_failed_first_signal_does_not_complete_group_dispatch(self):
        process = self.process(live=True)
        denied = PermissionError(errno.EPERM, 'denied')
        with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=[denied, None]) as kill:
            with self.assertRaises(PermissionError) as raised:
                process.cancel(124)
            self.assertIs(raised.exception, denied)
            self.assertTrue(process.active)
            process._kill()
            process.cancel(143)
            process._kill()
        self.assertEqual(kill.call_args_list,
                         [call(process.child.pid, signal.SIGKILL)] * 2)

    def test_successful_dispatch_does_not_mask_a_later_reap_failure(self):
        process = self.process()
        error = OSError(errno.ECHILD, 'uncertain reap')
        process.child.wait.side_effect = error
        with patch.object(coverage_io.os, 'killpg') as kill:
            process.cancel(124)
            for cleanup in (process.wait, process.__exit__, lambda: process.cancel(143)):
                with self.assertRaises(OSError) as raised:
                    cleanup()
                self.assertIs(raised.exception, error)
        kill.assert_called_once_with(process.child.pid, signal.SIGKILL)
        process.child.wait.assert_called_once_with(timeout=0)
        self.assertFalse(process.active)
        self.assertIs(process.cleanup_error, error)

    def process(self, *, live=False, during_wait=None):
        process = coverage_io._CaptureProcess(['owned'], None, None, None)
        child = Mock(pid=12345, returncode=None, stderr=io.BytesIO())
        process.child, process.active = child, True

        def wait(timeout=None):
            if timeout == 0:
                self.assertFalse(process.active, 'signals must be disabled before reaping')
                if during_wait is not None:
                    during_wait(process)
                if live:
                    raise subprocess.TimeoutExpired('owned', timeout)
            child.returncode = 0
            return 0

        child.wait.side_effect = wait
        return process

    def test_normal_wait_disarms_before_a_reentrant_signal_after_reaping(self):
        process = self.process()

        def wait(timeout):
            self.assertIn(timeout, (0, None))
            self.assertFalse(process.active)
            process.child.returncode = 0
            process._signal(signal.SIGTERM, None)
            return 0

        process.child.wait.side_effect = wait
        with patch.object(coverage_io.os, 'killpg') as killpg:
            self.assertEqual(process.wait(), 128 + signal.SIGTERM)
            process.__exit__()
        killpg.assert_not_called()
        self.assertFalse(process.active)

    def test_normal_wait_replays_cancellation_if_the_disarmed_wait_times_out(self):
        process = self.process()
        attempts = 0

        def wait(timeout):
            nonlocal attempts
            self.assertEqual(timeout, 0)
            self.assertFalse(process.active)
            attempts += 1
            if attempts == 1:
                process._signal(signal.SIGTERM, None)
                raise subprocess.TimeoutExpired('owned', timeout)
            process.child.returncode = -signal.SIGKILL
            return process.child.returncode

        def killpg(pid, number):
            self.assertEqual((pid, number), (process.child.pid, signal.SIGKILL))
            self.assertTrue(process.active)
            self.assertIsNone(process.child.returncode)

        process.child.wait.side_effect = wait
        with patch.object(coverage_io.os, 'killpg', side_effect=killpg) as kill:
            self.assertEqual(process.wait(), 128 + signal.SIGTERM)
        self.assertEqual(attempts, 2)
        self.assertFalse(process.active)
        kill.assert_called_once_with(process.child.pid, signal.SIGKILL)

    def test_normal_wait_failure_stays_disarmed_on_later_cleanup(self):
        for error in (OSError(errno.ECHILD, 'wait failed'), KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(error=error):
                process = self.process()
                process.child.wait.side_effect = error
                with patch.object(coverage_io.os, 'killpg') as killpg:
                    for action in (process.wait, process.__exit__, lambda: process.cancel(124)):
                        with self.assertRaises(type(error)) as raised:
                            action()
                        self.assertIs(raised.exception, error)
                self.assertFalse(process.active)
                process.child.wait.assert_called_once_with(timeout=0)
                killpg.assert_not_called()

    def test_reap_timeout_cannot_rearm_an_already_inactive_identity(self):
        process = self.process()
        process.active = False
        process.child.wait.side_effect = subprocess.TimeoutExpired('owned', 0)
        with self.assertRaises(subprocess.TimeoutExpired):
            process._reap(timeout=0)
        self.assertFalse(process.active)

    def test_exit_disarms_before_a_reentrant_signal_after_reaping(self):
        process = self.process()

        def wait(timeout):
            self.assertIsNone(timeout)
            self.assertFalse(process.active)
            process.child.returncode = 0
            process._signal(signal.SIGTERM, None)
            return 0

        process.child.wait.side_effect = wait
        with patch.object(coverage_io.os, 'killpg') as killpg:
            process.__exit__()
        killpg.assert_called_once_with(process.child.pid, signal.SIGKILL)
        process.child.wait.assert_called_once_with(timeout=None)
        self.assertFalse(process.active)
        self.assertTrue(process.child.stderr.closed)

    def test_darwin_eperm_with_live_leader_fails_without_waiting(self):
        process = self.process(live=True)
        denied = PermissionError(errno.EPERM, 'denied')
        with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=denied) as killpg:
            with self.assertRaises(PermissionError) as raised:
                process.cancel(124)
            self.assertIs(raised.exception, denied)
            self.assertTrue(process.active)
            self.assertIsNone(process.child.returncode)
            process.child.wait.assert_called_once_with(timeout=0)
            with self.assertRaises(PermissionError):
                process._kill()
        self.assertEqual(killpg.call_args_list,
                         [call(process.child.pid, signal.SIGKILL)] * 2)
        self.assertIsNone(process.cleanup_error)

    def test_live_permission_failure_keeps_owned_group_retry_available(self):
        for platform in ('darwin', 'linux'):
            with self.subTest(platform=platform):
                process = self.process(live=True)
                denied = PermissionError(errno.EPERM, 'denied')
                with patch.object(coverage_io.sys, 'platform', platform), \
                        patch.object(coverage_io.os, 'killpg', side_effect=[denied, None]) as killpg:
                    with self.assertRaises(PermissionError) as raised:
                        process._kill()
                    self.assertIs(raised.exception, denied)
                    self.assertTrue(process.active)
                    self.assertIsNone(process.cleanup_error)
                    process._kill()
                self.assertEqual(killpg.call_args_list,
                                 [call(process.child.pid, signal.SIGKILL)] * 2)

    def test_unexpected_reap_error_remains_disarmed_and_cannot_wait_on_exit(self):
        for error in (OSError(errno.ECHILD, 'wait failed'),
                      InterruptedError(errno.EINTR, 'interrupted'),
                      KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(error=error):
                process = self.process()
                process.child.wait.side_effect = error
                with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                        patch.object(coverage_io.os, 'killpg',
                                     side_effect=PermissionError(errno.EPERM, 'denied')) as killpg:
                    for cleanup in (process._kill, process.__exit__, lambda: process.cancel(124)):
                        with self.assertRaises(type(error)) as raised:
                            cleanup()
                        self.assertIs(raised.exception, error)
                self.assertFalse(process.active)
                self.assertIs(process.cleanup_error, error)
                process.child.wait.assert_called_once_with(timeout=0)
                killpg.assert_called_once_with(process.child.pid, signal.SIGKILL)

    def test_unexpected_probe_error_cannot_erase_failure_after_reaping(self):
        for error in (OSError(errno.EIO, 'probe failed'), RuntimeError('probe interrupted'),
                      KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(error=error):
                process = self.process()
                with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                        patch.object(coverage_io.os, 'killpg', side_effect=[
                            PermissionError(errno.EPERM, 'denied'), error]) as killpg:
                    for cleanup in (process._kill, process.__exit__, lambda: process.cancel(124)):
                        with self.assertRaises(type(error)) as raised:
                            cleanup()
                        self.assertIs(raised.exception, error)
                self.assertFalse(process.active)
                self.assertIs(process.cleanup_error, error)
                process.child.wait.assert_called_once_with(timeout=0)
                self.assertEqual(killpg.call_args_list,
                                 [call(process.child.pid, signal.SIGKILL), call(process.child.pid, 0)])

    def test_reaped_leader_with_present_or_denied_group_remains_failure(self):
        for result in (None, PermissionError(errno.EPERM, 'group denied')):
            with self.subTest(probe=result):
                process = self.process()
                denied = PermissionError(errno.EPERM, 'initial denial')
                expected = result if isinstance(result, PermissionError) else denied
                with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                        patch.object(coverage_io.os, 'killpg', side_effect=[denied, result]) as killpg:
                    with self.assertRaises(PermissionError) as raised:
                        process.cancel(124)
                    self.assertIs(raised.exception, expected)
                    self.assertFalse(process.active)
                    self.assertEqual(process.child.returncode, 0)
                    # Reaping must neither erase a failure nor allow a later
                    # cancellation/exit to signal a possibly recycled PID.
                    for cleanup in (lambda: process.cancel(143), process.__exit__):
                        with self.assertRaises(PermissionError) as repeated:
                            cleanup()
                        self.assertIs(repeated.exception, expected)
                self.assertEqual(killpg.call_args_list,
                                 [call(process.child.pid, signal.SIGKILL), call(process.child.pid, 0)])
                process.child.wait.assert_called_once_with(timeout=0)

    def test_reaped_leader_and_absent_group_disable_later_destructive_signals(self):
        process = self.process(during_wait=lambda owned: owned._signal(signal.SIGTERM, None))
        denied = PermissionError(errno.EPERM, 'denied')

        def killpg(pid, number):
            if number == signal.SIGKILL:
                self.assertTrue(process.active)
                self.assertIsNone(process.child.returncode)
                raise denied
            self.assertFalse(process.active)
            self.assertEqual(process.child.returncode, 0)
            raise ProcessLookupError(errno.ESRCH, 'gone')

        with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=killpg) as kill:
            process._kill()
            self.assertIsNone(process.cleanup_error)
            process.cancel(124)
            process.__exit__()
        self.assertFalse(process.active)
        self.assertEqual(process.cancelled_status, 128 + signal.SIGTERM)
        self.assertEqual(kill.call_args_list,
                         [call(process.child.pid, signal.SIGKILL), call(process.child.pid, 0)])
        self.assertTrue(process.child.stderr.closed)

    def test_signal_reentry_cannot_reap_before_an_outer_destructive_signal(self):
        process = self.process()
        entered = False

        def killpg(pid, number):
            nonlocal entered
            if number == signal.SIGKILL:
                if not entered:
                    entered = True
                    process._signal(signal.SIGTERM, None)
                self.assertTrue(process.active)
                self.assertIsNone(process.child.returncode, 'nested cleanup reaped before outer signal')
                raise PermissionError(errno.EPERM, 'denied')
            self.assertEqual(number, 0)
            self.assertFalse(process.active)
            self.assertEqual(process.child.returncode, 0)
            raise ProcessLookupError(errno.ESRCH, 'gone')

        with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=killpg) as kill:
            process._kill()
            process.cancel(124)
        self.assertEqual(process.cancelled_status, 128 + signal.SIGTERM)
        self.assertEqual(kill.call_args_list,
                         [call(process.child.pid, signal.SIGKILL), call(process.child.pid, 0)])
        process.child.wait.assert_called_once_with(timeout=0)

    def test_unrelated_platform_permission_and_probe_errors_propagate(self):
        for platform, number in (('linux', errno.EPERM), ('darwin', errno.EACCES)):
            with self.subTest(platform=platform, errno=number):
                process = self.process()
                error = PermissionError(number, 'denied')
                with patch.object(coverage_io.sys, 'platform', platform), \
                        patch.object(coverage_io.os, 'killpg', side_effect=error), \
                        self.assertRaises(PermissionError) as raised:
                    process._kill()
                self.assertIs(raised.exception, error)
                process.child.wait.assert_not_called()
        process = self.process()
        error = OSError(errno.EIO, 'probe failed')
        with patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=[PermissionError(errno.EPERM, 'denied'), error]):
            for cleanup in (process._kill, process.__exit__):
                with self.assertRaises(OSError) as raised:
                    cleanup()
                self.assertIs(raised.exception, error)

    def test_parser_error_survives_verified_absent_group_cleanup(self):
        process = self.process()
        process.child.stderr = io.BytesIO(b'COVBRANCH:m:1:garbage\n')
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(coverage_io.subprocess, 'Popen', return_value=process.child), \
                patch.object(coverage_io.sys, 'platform', 'darwin'), \
                patch.object(coverage_io.os, 'killpg', side_effect=[
                    PermissionError(errno.EPERM, 'denied'), ProcessLookupError(errno.ESRCH, 'gone')]) as killpg, \
                contextlib.redirect_stdout(io.StringIO()):
            # The real context manager owns this fake child. Its nonblocking
            # wait is the state witness, rather than the PID-only old test.
            process.child.wait.side_effect = None
            process.child.wait.return_value = 0
            with self.assertRaisesRegex(ValueError, 'Malformed branch outcome'):
                coverage_io.capture(['owned'], Path(directory)/'out', Path(directory)/'err.gz')
        self.assertEqual(killpg.call_args_list,
                         [call(process.child.pid, signal.SIGKILL), call(process.child.pid, 0)])
        self.assertTrue(process.child.stderr.closed)


@unittest.skipUnless(os.name == 'posix', 'POSIX coverage process groups')
class CoverageLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='coverage lifecycle ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'worker.py').write_text(WORKER)
        self.environment = os.environ.copy()
        self.environment.pop(coverage_io.DEADLINE_ENV, None)
        self.environment['PYTHONPATH'] = str(Path(coverage_io.__file__).parent)
        self.environment['PYTHONDONTWRITEBYTECODE'] = '1'

    def ready(self, name='grandchild.pid'):
        deadline = time.monotonic() + 4
        while not (self.root / name).exists():
            if time.monotonic() >= deadline:
                self.fail('fake coverage process did not start: ' + name)
            time.sleep(0.01)

    def stopped(self, pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        # A killed orphan can briefly remain a zombie until the host reaps it.
        stat = Path('/proc') / str(pid) / 'stat'
        if stat.exists():
            try:
                return stat.read_text().rpartition(') ')[2].startswith('Z ')
            except (FileNotFoundError, ProcessLookupError):
                # The process can be reaped after exists() or open().
                return True
        return False

    def test_stopped_accepts_process_reaped_during_stat_read(self):
        for error in (FileNotFoundError(errno.ENOENT, 'gone'),
                      ProcessLookupError(errno.ESRCH, 'gone')):
            with self.subTest(error=type(error).__name__), \
                    patch.object(os, 'kill'), \
                    patch.object(Path, 'exists', return_value=True), \
                    patch.object(Path, 'read_text', side_effect=error):
                self.assertTrue(self.stopped(123))

    def test_stopped_distinguishes_live_and_zombie_processes(self):
        for state, expected in (('R', False), ('S', False), ('Z', True)):
            with self.subTest(state=state), \
                    patch.object(os, 'kill'), \
                    patch.object(Path, 'exists', return_value=True), \
                    patch.object(Path, 'read_text',
                                 return_value='123 (worker) ' + state + ' 1 2'):
                self.assertEqual(self.stopped(123), expected)

    def test_stopped_without_procfs_does_not_assume_exit(self):
        with patch.object(os, 'kill'), \
                patch.object(Path, 'exists', return_value=False), \
                patch.object(Path, 'read_text') as read:
            self.assertFalse(self.stopped(123))
        read.assert_not_called()

    def test_stopped_propagates_unrelated_stat_errors(self):
        for error in (PermissionError(errno.EACCES, 'denied'),
                      OSError(errno.EIO, 'read failed')):
            with self.subTest(error=type(error).__name__), \
                    patch.object(os, 'kill'), \
                    patch.object(Path, 'exists', return_value=True), \
                    patch.object(Path, 'read_text', side_effect=error), \
                    self.assertRaises(type(error)) as raised:
                self.stopped(123)
            self.assertIs(raised.exception, error)

    def assert_tree_stopped(self):
        pids = [int((self.root / (role + '.pid')).read_text())
                for role in ('child', 'grandchild')]
        deadline = time.monotonic() + 3
        while not all(self.stopped(pid) for pid in pids):
            if time.monotonic() >= deadline:
                self.fail('capture left a live descendant: ' + repr(pids))
            time.sleep(0.01)
        self.assertFalse(Path((self.root / 'temporary').read_text()).exists())

    def cleanup_process(self, process):
        if process.poll() is None:
            process.terminate()
        try:
            process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        # A failed assertion must not leave the deliberately hanging fixture.
        path = self.root / 'child.pid'
        if not path.exists():
            path = self.root / 'owned-child.pid'
        if path.exists():
            pid = int(path.read_text())
            if not self.stopped(pid):
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(pid, signal.SIGKILL)
        # An orphaned capture may still hold these pipes until its tree stops.
        process.communicate(timeout=2)

    def launch(self, mode='valid', seconds=4):
        environment = self.environment | {
            coverage_io.DEADLINE_ENV: repr(time.monotonic() + seconds)}
        process = subprocess.Popen(
            [sys.executable, '-c', DRIVER, str(self.root), mode],
            env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        self.addCleanup(self.cleanup_process, process)
        return process

    def capture_prepared_tree(self):
        # Fixture startup is outside the unchanged 0.6-second capture budget.
        # The real capture still reads and enforces one absolute deadline.
        process = subprocess.Popen(
            [sys.executable, '-c', PREPARED_DRIVER, str(self.root)],
            env=self.environment | {'TMPDIR': str(self.root)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        self.addCleanup(self.cleanup_process, process)
        self.ready()
        temporary = self.root / 'deadline.tmp'
        temporary.write_text(repr(time.monotonic() + 0.6))
        temporary.replace(self.root / 'deadline')
        output, error = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 124, output + error)
        self.assert_tree_stopped()

    def test_shared_deadline_kills_child_and_grandchild(self):
        self.capture_prepared_tree()

    def test_shared_deadline_allows_slow_fixture_startup(self):
        (self.root / 'worker.py').write_text(WORKER.replace(
            'role, mode = sys.argv[2:4]',
            "role, mode = sys.argv[2:4]\nif role == 'grandchild': time.sleep(0.7)"))
        self.capture_prepared_tree()

    def test_cancellation_kills_child_and_grandchild(self):
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(signal=number):
                for path in self.root.glob('*.pid'):
                    path.unlink()
                process = self.launch()
                self.ready()
                process.send_signal(number)
                output, error = process.communicate(timeout=4)
                self.assertEqual(process.returncode, 128 + number, output + error)
                self.assert_tree_stopped()

    def test_parser_failure_kills_child_and_grandchild(self):
        process = self.launch(mode='malformed')
        output, error = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 1, output + error)
        self.assertIn('Legacy compound coverage is ambiguous', error)
        self.assert_tree_stopped()

    def test_output_failure_kills_child_and_grandchild(self):
        command = [sys.executable, str(self.root / 'worker.py'),
                   str(self.root), 'child', 'valid']
        with patch.object(coverage_io.gzip.GzipFile, 'write',
                          side_effect=OSError('injected output failure')), \
                contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaisesRegex(OSError, 'injected output failure'):
            coverage_io.capture(command, self.root / 'out', self.root / 'err.gz')
        self.assert_tree_stopped()

    def test_expired_queued_capture_does_not_start_a_child(self):
        with patch.dict(os.environ, {coverage_io.DEADLINE_ENV: repr(time.monotonic() - 1)}), \
                patch.object(coverage_io.subprocess, 'Popen') as popen, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coverage_io.capture(['unused'], self.root / 'out',
                                                 self.root / 'err.gz'), 124)
        popen.assert_not_called()

    def test_deadline_also_applies_after_stderr_closes(self):
        started = time.monotonic()
        with patch.dict(os.environ, {coverage_io.DEADLINE_ENV: repr(time.monotonic() + 0.15)}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coverage_io.capture(
                [sys.executable, '-c', 'import os,time;os.close(2);time.sleep(30)'],
                self.root / 'out', self.root / 'err.gz'), 124)
        self.assertLess(time.monotonic() - started, 2)

    def test_signal_during_spawn_is_applied_after_child_assignment(self):
        real_popen = subprocess.Popen

        def spawn(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            signal.raise_signal(signal.SIGTERM)
            return child

        old_handler = signal.getsignal(signal.SIGTERM)
        with patch.object(coverage_io.subprocess, 'Popen', side_effect=spawn), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coverage_io.capture(
                [sys.executable, '-c', 'import time;time.sleep(30)'],
                self.root / 'out', self.root / 'err.gz'), 143)
        self.assertEqual(signal.getsignal(signal.SIGTERM), old_handler)

    def capture_after_group_alarm(self):
        bootstrap = '''import os, pathlib, subprocess, sys, time
root = pathlib.Path(sys.argv[1])
capture = subprocess.Popen([sys.executable, '-c', sys.argv[2], str(root),
                            str(os.getpid())])
while not (root / 'start-group').exists():
    if capture.poll() is not None:
        raise RuntimeError('prepared capture exited before group startup')
    time.sleep(0.01)
os.execv(sys.executable,
         [sys.executable, sys.argv[4], 'group', '--seconds', '0.9', '--',
          sys.executable, '-c', sys.argv[3], str(root)])
'''
        scheduler = '''import os, pathlib, sys, time
root = pathlib.Path(sys.argv[1])
time.sleep(0.25)
deadline = root / 'deadline.tmp'
deadline.write_text(os.environ['THREEMOJO_COVERAGE_DEADLINE'])
deadline.replace(root / 'deadline')
time.sleep(30)
'''
        process = subprocess.Popen(
            [sys.executable, '-c', bootstrap, str(self.root), PREPARED_DRIVER,
             scheduler, coverage_io.__file__],
            env=self.environment | {'TMPDIR': str(self.root)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        self.addCleanup(self.cleanup_process, process)
        # Start the real group alarm only after the owned fixture is ready.
        # Exec keeps the capture's parent PID, so that alarm still orphans it.
        self.ready()
        started = time.monotonic()
        (self.root / 'start-group').touch()
        output, error = process.communicate(timeout=4)
        self.assertEqual(process.returncode, -signal.SIGALRM, output + error)
        self.assertLess(time.monotonic() - started, 2.5)
        self.assertEqual((self.root / 'status').read_text(), '124')
        self.assert_tree_stopped()

    def test_group_alarm_does_not_orphan_delayed_capture(self):
        self.capture_after_group_alarm()

    def test_group_alarm_allows_slow_fixture_startup(self):
        (self.root / 'worker.py').write_text(WORKER.replace(
            'role, mode = sys.argv[2:4]',
            "role, mode = sys.argv[2:4]\nif role == 'grandchild': time.sleep(0.7)"))
        self.capture_after_group_alarm()

    def test_make_uses_one_shared_group_budget(self):
        make = (Path(coverage_io.__file__).parent.parent / 'Makefile').read_text()
        recipe = make[make.index('coverage-capture:\n'):make.index('\ncoverage-report:')]
        self.assertIn('tools/coverage_io.py group --seconds $(COV_BUDGET) --', recipe)
        self.assertNotIn('alarm shift', recipe)
        self.assertEqual(recipe.count('tools/coverage_io.py capture'), 1)


if __name__ == '__main__':
    unittest.main()
