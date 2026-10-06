# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free fake-proc and lifecycle tests for the diagnostic wrapper."""

import contextlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import compiler_telemetry as telemetry


def stat_text(pid, ppid=1, start=100, ticks=20, rss=10, threads=1,
              state='S', name='compiler (worker)'):
    fields = ['0'] * 50
    for index, value in {0: state, 1: ppid, 11: ticks, 12: 0, 17: threads,
                         19: start, 21: rss}.items():
        fields[index] = str(value)
    return f'{pid} ({name}) ' + ' '.join(fields)


class FakeProcTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.proc = self.root / 'proc'
        (self.proc / 'self').mkdir(parents=True)
        self.cg = self.root / 'cgroup'
        (self.cg / 'job').mkdir(parents=True)
        (self.proc / 'self/mountinfo').write_text(
            f'1 0 0:1 / {self.cg} rw - cgroup2 none rw\n')
        self.process(100)
        (self.proc / '100/cgroup').write_text('0::/job\n')
        self.counters(1, 0)
        self.reader = telemetry.ProcReader(self.proc)

    def process(self, pid, ppid=1, start=100, ticks=20, threads=1):
        folder = self.proc / str(pid)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'stat').write_text(stat_text(pid, ppid, start, ticks, threads=threads))
        for tid in range(pid, pid + threads):
            task = folder / 'task' / str(tid)
            task.mkdir(parents=True, exist_ok=True)
            (task / 'stat').write_text(stat_text(tid, ppid, start, ticks))
            (task / 'wchan').write_text('futex_wait_queue')
            (task / 'children').write_text('')

    def counters(self, oom, kills):
        for name in ('memory.events', 'memory.events.local'):
            (self.cg / 'job' / name).write_text(
                f'low 0\nhigh 0\nmax 0\noom {oom}\noom_kill {kills}\noom_group_kill 0\n')

    def sampler(self):
        sampler = telemetry.Sampler(100, self.reader, clock=iter([10, 70, 130]).__next__)
        self.addCleanup(sampler.close)
        sampler.hz, sampler.page_kib = 100, 4
        return sampler

    def test_stat_handles_spaces_and_parentheses_without_exposing_name(self):
        result = telemetry.parse_stat(stat_text(42, name='a ) strange ( name)'))
        self.assertEqual((result['pid'], result['ticks'], result['start']), (42, 20, 100))
        self.assertNotIn('name', result)

    def test_nonleader_children_are_seen_but_unrelated_processes_are_not_read(self):
        self.process(100, threads=2)
        self.process(200, ppid=100)
        self.process(999, ppid=1)
        (self.proc / '100/task/101/children').write_text('200')
        with patch.object(self.reader, 'read', wraps=self.reader.read) as read:
            result = self.reader.tree(100)
        self.assertEqual([r['pid'] for r in result], [100, 200])
        paths = [str(call.args[0]) for call in read.call_args_list]
        self.assertFalse(any('/999/' in path for path in paths))
        self.assertFalse(any(part in path for path in paths
                             for part in ('environ', 'cmdline', '/mem', '/maps', '/stack')))

    def test_cpu_deltas_and_rss_do_not_double_count_threads(self):
        self.process(100, ticks=100, threads=2)
        sampler = self.sampler()
        first = sampler.sample()
        self.process(100, ticks=250, threads=2)
        second = sampler.sample()
        self.assertIsNone(first['observed_cpu_delta_s'])
        self.assertEqual(second['observed_cpu_delta_s'], 1.5)
        self.assertEqual(second['interval_s'], 60)
        self.assertEqual(second['tree_rss_kib_approx'], 40)
        self.assertEqual(second['processes'][0]['thread_states'], {'S': 2})

    def test_reused_child_pid_has_no_false_delta(self):
        self.process(200, ppid=100, ticks=1000)
        (self.proc / '100/task/100/children').write_text('200')
        sampler = self.sampler()
        sampler.sample()
        self.process(200, ppid=100, start=200, ticks=10)
        result = sampler.sample()
        child = next(p for p in result['processes'] if p['pid'] == 200)
        self.assertIsNone(child['cpu_delta_s'])

    def test_replaced_root_is_not_sampled_or_mapped_to_a_cgroup(self):
        sampler = self.sampler()
        sampler.sample()
        self.process(100, start=999)
        with patch.object(self.reader, 'cgroup', wraps=self.reader.cgroup) as cgroup:
            result = sampler.sample()
        self.assertEqual(result['processes'], [])
        self.assertIsNone(result['tree_rss_kib_approx'])
        cgroup.assert_not_called()

    def test_candidate_must_still_be_a_child_of_the_discovered_parent(self):
        self.process(200, ppid=999)
        (self.proc / '100/task/100/children').write_text('200')
        self.assertEqual([r['pid'] for r in self.reader.tree(100)], [100])

    def test_missing_and_denied_metadata_are_unavailable_not_zero(self):
        (self.proc / '100/task/100/wchan').unlink()
        (self.cg / 'job/memory.events').unlink()
        result = self.sampler().sample()
        self.assertGreater(result['unavailable_reads'], 0)
        self.assertIsNone(result['cgroup_oom_shared_context']['memory.events'])
        with patch('compiler_telemetry.os.open', side_effect=PermissionError):
            self.assertIsNone(self.reader.read(self.proc / '100/stat'))

    def test_traversal_and_thread_caps_are_visible(self):
        self.process(100, threads=40)
        for pid in range(200, 220):
            self.process(pid, ppid=100)
        (self.proc / '100/task/100/children').write_text(' '.join(map(str, range(200, 220))))
        result = self.sampler().sample()
        self.assertLessEqual(len(result['processes']), telemetry.MAX_PROCESSES)
        self.assertLessEqual(result['processes'][0]['sampled_threads'], telemetry.MAX_THREADS)
        self.assertTrue(result['truncated'])

    def test_subtree_cgroup_mount_mapping_and_shared_counter_deltas(self):
        (self.proc / 'self/mountinfo').write_text(
            f'1 0 0:1 /host {self.cg} rw - cgroup2 none rw\n')
        (self.proc / '100/cgroup').write_text('0::/host/job\n')
        self.assertEqual(self.reader.cgroup(100), (self.cg / 'job').resolve())
        sampler = self.sampler()
        sampler.sample()
        self.counters(2, 1)
        result = sampler.sample()
        self.assertEqual(result['cgroup_oom_delta']['memory.events']['oom_kill'], 1)

    def test_symlinked_cgroup_mount_preserves_mapping_and_counter_deltas(self):
        canonical = (self.cg / 'job').resolve()
        alias = self.root / 'cgroup-alias'
        alias.symlink_to(self.cg, target_is_directory=True)
        self.cg = alias
        self.assertNotEqual(self.cg / 'job', canonical)
        self.test_subtree_cgroup_mount_mapping_and_shared_counter_deltas()
        self.assertEqual(self.reader.cgroup(100), canonical)

    def test_unmappable_or_traversal_cgroup_never_uses_a_global_fallback(self):
        (self.proc / 'self/mountinfo').write_text(
            f'1 0 0:1 /host {self.cg} rw - cgroup2 none rw\n')
        for membership in ('0::/outside\n', '0::/host/../job\n', '4:memory:/host/job\n'):
            (self.proc / '100/cgroup').write_text(membership)
            self.assertIsNone(self.reader.cgroup(100))

    def test_changed_cgroup_does_not_reuse_counter_baselines(self):
        sampler = self.sampler()
        sampler.sample()
        (self.cg / 'other').mkdir()
        (self.cg / 'other/memory.events').write_text('oom 90\noom_kill 90\n')
        (self.proc / '100/cgroup').write_text('0::/other\n')
        self.assertIsNone(sampler.sample()['cgroup_oom_delta'])

    def test_pinned_process_directory_does_not_follow_a_reused_pid_path(self):
        self.process(100, threads=2)
        with self.reader.directory(self.proc / '100') as fd:
            (self.proc / '100').rename(self.proc / 'old-process')
            self.process(100, start=999, threads=8)
            records = self.reader.tree(100, (100, 100), root_fd=fd)
        self.assertEqual(records[0]['start'], 100)
        self.assertEqual(records[0]['sampled_threads'], 2)

    def test_terminal_oom_counter_uses_pinned_group_without_pid_lookup(self):
        sampler = self.sampler()
        sampler.sample()
        self.counters(2, 1)
        (self.proc / '100').rename(self.proc / 'finished-process')
        with patch.object(self.reader, 'inspect', side_effect=AssertionError('PID lookup')):
            terminal = sampler.terminal()
        self.assertEqual(terminal['cgroup_oom_delta']['memory.events']['oom_kill'], 1)
        sampler.close()
        self.assertIsNone(sampler.group_fd)

    def test_sampler_error_closes_an_already_pinned_cgroup(self):
        sampler = self.sampler()
        sample = sampler.sample
        opened = []
        def fail_after_open():
            sample()
            opened.append(sampler.group_fd)
            raise ValueError('fake telemetry failure')
        with patch.object(sampler, 'sample', side_effect=fail_after_open):
            with tempfile.TemporaryFile() as stream:
                status = telemetry.run_compiler([sys.executable, '-c', 'pass'],
                                                'tests/test_fake.mojo', stream.fileno(),
                                                sampler_factory=lambda pid: sampler)
        self.assertEqual(status, 0)
        self.assertTrue(opened)
        self.assertIsNone(sampler.group_fd)
        with self.assertRaises(OSError):
            os.fstat(opened[0])

    def test_record_size_and_logging_failure_are_bounded(self):
        with tempfile.TemporaryFile() as stream:
            telemetry.emit(stream.fileno(), 'tests/test_fake.mojo', {
                'processes': [{'pid': i, 'waits': 'x' * 1500} for i in range(8)]})
            stream.seek(0)
            data = stream.read()
        self.assertLessEqual(len(data), telemetry.MAX_LINE)
        self.assertGreater(json.loads(data)['processes_omitted_from_log'], 0)
        telemetry.emit(-1, 'tests/test_fake.mojo', {'event': 'test'})


class EmptySampler:
    def __init__(self, pid):
        self.pid = pid

    def sample(self):
        return {'processes': [], 'root_pid': self.pid}


class LifecycleTests(unittest.TestCase):
    def run_command(self, code, factory=EmptySampler):
        with tempfile.TemporaryFile() as stream:
            status = telemetry.run_compiler([sys.executable, '-c', code],
                                            'tests/test_fake.mojo', stream.fileno(),
                                            interval=0.02, sampler_factory=factory)
            stream.seek(0)
            records = [json.loads(line) for line in stream]
        return status, records

    def test_success_and_nonzero_exit_are_preserved_and_monitor_ends(self):
        for expected in (0, 7):
            status, records = self.run_command(f'import sys; sys.exit({expected})')
            self.assertEqual(status, expected)
            self.assertEqual(records[-1]['event'], 'compiler-exit')
            self.assertEqual(records[-1]['exit'], expected)

    def test_signal_exit_is_the_shell_status(self):
        status, _ = self.run_command('import os, signal; os.kill(os.getpid(), signal.SIGTERM)')
        self.assertEqual(status, 128 + signal.SIGTERM)

    def test_telemetry_error_does_not_change_compiler_result(self):
        class BrokenSampler(EmptySampler):
            def sample(self):
                raise PermissionError('details must not be logged')
        status, records = self.run_command('import sys; sys.exit(7)', BrokenSampler)
        self.assertEqual(status, 7)
        self.assertEqual(records[0]['event'], 'telemetry-unavailable')
        self.assertNotIn('details must not be logged', json.dumps(records))

    def test_periodic_sampling_adds_no_compiler_timeout(self):
        status, records = self.run_command('import time; time.sleep(0.12)')
        self.assertEqual(status, 0)
        self.assertGreaterEqual(sum(r['event'] == 'sample' for r in records), 2)

    def test_signal_receipt_is_forwarded_once_before_or_after_child_assignment(self):
        class Child:
            pid = 12345
            def poll(self):
                return None
            def wait(self, timeout=None):
                return 0
        for early in (True, False):
            def popen(*args, **kwargs):
                if early:
                    signal.raise_signal(signal.SIGTERM)
                return Child()
            def factory(pid):
                if not early:
                    signal.raise_signal(signal.SIGTERM)
                return EmptySampler(pid)
            with patch.object(telemetry.subprocess, 'Popen', side_effect=popen):
                with patch.object(telemetry.os, 'killpg') as send:
                    with tempfile.TemporaryFile() as stream:
                        status = telemetry.run_compiler(['fake'], 'tests/test_fake.mojo',
                                                        stream.fileno(), sampler_factory=factory)
            self.assertEqual(status, 143)
            send.assert_called_once_with(12345, signal.SIGTERM)

    def test_disabled_wrapper_execs_without_a_monitor(self):
        command = [sys.executable, str(Path(telemetry.__file__)), '--suite',
                   'tests/test_fake.mojo', '--', sys.executable, '-c',
                   'import os,sys; print(os.getpid()); sys.exit(11)']
        child = subprocess.Popen(command, env=os.environ | {'THREEMOJO_COMPILER_TELEMETRY': '0'},
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 11)
        self.assertEqual(int(stdout), child.pid)
        self.assertEqual(stderr, '')

    @unittest.skipUnless(sys.platform == 'linux', 'Linux process-group contract')
    def test_cancellation_reaches_only_the_owned_compiler_group(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker = root / 'worker.py'
            worker.write_text('''import pathlib,signal,sys,time,subprocess,os
root=pathlib.Path(sys.argv[1]); role=sys.argv[2]
def stop(sig, frame):
    (root/(role+'.signal')).write_text(str(sig))
    if role=='compiler':
        child.wait(timeout=3)
    sys.exit(0)
signal.signal(signal.SIGTERM,stop)
if role=='compiler':
    child=subprocess.Popen([sys.executable,__file__,str(root),'worker'])
(root/(role+'.ready')).write_text(str(os.getpid()))
while True: time.sleep(0.02)
''')
            script = ('import compiler_telemetry as t,sys; '
                      'sys.exit(t.run_compiler(sys.argv[1:],"tests/test_fake.mojo",2,interval=0.02))')
            child = subprocess.Popen([sys.executable, '-c', script, sys.executable,
                                      str(worker), str(root), 'compiler'],
                                     cwd=Path(telemetry.__file__).parent,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            compiler_pid = None
            try:
                deadline = time.monotonic() + 5
                while not (root / 'worker.ready').exists():
                    if time.monotonic() > deadline:
                        self.fail('fake compiler tree did not start')
                    time.sleep(0.01)
                compiler_pid = int((root / 'compiler.ready').read_text())
                child.send_signal(signal.SIGTERM)
                _, output = child.communicate(timeout=5)
                self.assertEqual(child.returncode, 143, output)
                for role in ('compiler', 'worker'):
                    self.assertEqual(int((root / (role + '.signal')).read_text()), signal.SIGTERM)
                self.assertEqual(json.loads(output.splitlines()[-1])['event'], 'compiler-exit')
            finally:
                if child.poll() is None:
                    if compiler_pid is not None:
                        with contextlib.suppress(ProcessLookupError):
                            os.killpg(compiler_pid, signal.SIGKILL)
                    child.kill()
                    child.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main()
