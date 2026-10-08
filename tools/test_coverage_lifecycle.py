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
from unittest.mock import patch

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
from unittest.mock import patch
import coverage_io
root = pathlib.Path(sys.argv[1])
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
            process.communicate(timeout=2)
        # A failed assertion must not leave the deliberately hanging fixture.
        path = self.root / 'child.pid'
        if not path.exists():
            path = self.root / 'owned-child.pid'
        if path.exists():
            pid = int(path.read_text())
            if not self.stopped(pid):
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(pid, signal.SIGKILL)

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

    def test_group_alarm_does_not_orphan_delayed_capture(self):
        scheduler = '''import os, pathlib, subprocess, sys, time
root = pathlib.Path(sys.argv[1])
(root / 'deadline').write_text(os.environ['THREEMOJO_COVERAGE_DEADLINE'])
time.sleep(0.25)
subprocess.Popen([sys.executable, '-c', sys.argv[2], str(root), 'valid'])
time.sleep(30)
'''
        started = time.monotonic()
        process = subprocess.Popen(
            [sys.executable, coverage_io.__file__, 'group', '--seconds', '0.9', '--',
             sys.executable, '-c', scheduler, str(self.root), DRIVER],
            env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        self.addCleanup(self.cleanup_process, process)
        self.ready()
        output, error = process.communicate(timeout=4)
        self.assertEqual(process.returncode, -signal.SIGALRM, output + error)
        self.assertLess(time.monotonic() - started, 2.5)
        self.assertEqual((self.root / 'status').read_text(), '124')
        self.assert_tree_stopped()

    def test_make_uses_one_shared_group_budget(self):
        make = (Path(coverage_io.__file__).parent.parent / 'Makefile').read_text()
        recipe = make[make.index('coverage-capture:\n'):make.index('\ncoverage-report:')]
        self.assertIn('tools/coverage_io.py group --seconds $(COV_BUDGET) --', recipe)
        self.assertNotIn('alarm shift', recipe)
        self.assertEqual(recipe.count('tools/coverage_io.py capture'), 1)


if __name__ == '__main__':
    unittest.main()
