# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Observe one CPU-suite compiler without changing its workload or time limit.

Only THREEMOJO_COMPILER_TELEMETRY=1 on Linux enables sampling. Otherwise
exec the supplied command. Read only its best-effort descendant tree and
its readable cgroup-v2 OOM counters. Never inspect command lines, environment,
process memory, stacks, unrelated processes, or change resource limits.
"""

import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timezone
import itertools
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import subprocess
import sys
import time

INTERVAL = 60.0
MAX_PROCESSES = 8
MAX_THREADS = 32
MAX_CHILDREN = 32
MAX_LINE = 4096
OOM_KEYS = ('oom', 'oom_kill', 'oom_group_kill')


def parse_stat(text):
    """Return only scheduling/accounting fields, preserving PID identity."""
    end = text.rfind(')')
    if end < 0:
        raise ValueError('missing process name delimiter')
    fields = text[end + 1:].split()
    return {
        'pid': int(text.split('(', 1)[0]), 'ppid': int(fields[1]),
        'state': fields[0], 'ticks': int(fields[11]) + int(fields[12]),
        'threads': int(fields[17]), 'start': int(fields[19]),
        'rss_pages': max(0, int(fields[21])),
    }


def identity(stat):
    """Return a key that prevents CPU deltas across reused PIDs."""
    return stat['pid'], stat['start']


class ProcReader:
    """Read bounded kernel metadata, starting only from an owned compiler."""

    def __init__(self, root=Path('/proc')):
        self.root = Path(root)
        self.unavailable = 0
        self.truncated = False

    def open_dir(self, path, dir_fd=None):
        try:
            return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                           dir_fd=dir_fd)
        except OSError:
            self.unavailable += 1
            return None

    @contextmanager
    def directory(self, path, dir_fd=None):
        fd = self.open_dir(path, dir_fd)
        try:
            yield fd
        finally:
            if fd is not None:
                os.close(fd)

    def read(self, path, limit=4096, dir_fd=None):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
            with os.fdopen(fd, encoding='ascii', errors='replace') as stream:
                text = stream.read(limit + 1)
            if len(text) > limit:
                self.truncated = True
                return None
            return text
        except (OSError, ValueError):
            self.unavailable += 1
            return None

    def entries(self, path, limit, dir_fd=None):
        with self.directory(path, dir_fd) as fd:
            if fd is None:
                return []
            try:
                with os.scandir(fd) as entries:
                    found = list(itertools.islice(entries, limit + 1))
                if len(found) > limit:
                    self.truncated = True
                return sorted(int(item.name) for item in found[:limit]
                              if item.name.isdecimal())
            except OSError:
                self.unavailable += 1
                return []

    def stat(self, path=Path('.'), dir_fd=None):
        text = self.read(Path(path) / 'stat', dir_fd=dir_fd)
        if text is not None:
            try:
                return parse_stat(text)
            except (ValueError, IndexError):
                self.unavailable += 1
        return None

    def tree(self, root_pid, root_identity=None, root_fd=None):
        """Read bounded descendants through pinned process-directory FDs.

        children is racy, so absent/reparented children can be missed. Pinned
        /proc directory FDs cannot retarget an unrelated reused PID. No scan
        of the system-wide PID directory is used as a fallback.
        """
        if root_fd is None:
            with self.directory(self.root / str(root_pid)) as fd:
                return [] if fd is None else self.tree(root_pid, root_identity, fd)
        queue = [(root_pid, os.dup(root_fd))]
        seen, records = set(), []
        try:
            while queue and len(seen) < MAX_PROCESSES:
                pid, fd = queue.pop(0)
                try:
                    if pid in seen:
                        continue
                    seen.add(pid)
                    stat = self.stat(dir_fd=fd)
                    if stat is None or stat['pid'] != pid:
                        continue
                    if pid == root_pid and root_identity not in (None, identity(stat)):
                        continue
                    states, waits, children = Counter(), Counter(), []
                    tids = self.entries('task', MAX_THREADS, dir_fd=fd)
                    for tid in tids:
                        task = Path('task') / str(tid)
                        thread = self.stat(task, dir_fd=fd)
                        if thread is not None:
                            states[thread['state']] += 1
                        wait = self.read(task / 'wchan', 128, dir_fd=fd)
                        if wait is not None:
                            name = re.sub(r'[^A-Za-z0-9_]', '', wait)[:48] or 'unavailable'
                            waits[name] += 1
                        child_text = self.read(task / 'children', 1024, dir_fd=fd)
                        if child_text is not None:
                            words = child_text.split()
                            if len(words) > MAX_CHILDREN:
                                self.truncated = True
                            children.extend(int(word) for word in words[:MAX_CHILDREN]
                                            if word.isdecimal())
                    after = self.stat(dir_fd=fd)
                    if after is None or identity(after) != identity(stat):
                        continue
                    stat['thread_states'] = dict(sorted(states.items()))
                    stat['thread_waits'] = dict(waits.most_common(4))
                    stat['sampled_threads'] = sum(states.values())
                    stat['wait_kinds_omitted'] = max(0, len(waits) - 4)
                    records.append(stat)
                    for child in sorted(set(children)):
                        if child in seen:
                            continue
                        if len(queue) + len(seen) >= MAX_PROCESSES:
                            self.truncated = True
                            break
                        child_fd = self.open_dir(self.root / str(child))
                        if child_fd is None:
                            continue
                        child_stat = self.stat(dir_fd=child_fd)
                        parent_stat = self.stat(dir_fd=fd)
                        if (child_stat is not None and child_stat['ppid'] == pid
                                and parent_stat is not None
                                and identity(parent_stat) == identity(stat)):
                            queue.append((child, child_fd))
                        else:
                            os.close(child_fd)
                finally:
                    os.close(fd)
            if queue:
                self.truncated = True
            return records
        finally:
            for _, fd in queue:
                os.close(fd)

    def inspect(self, pid, expected):
        with self.directory(self.root / str(pid)) as fd:
            if fd is None:
                return [], None
            records = self.tree(pid, expected, fd)
            return records, self.cgroup(pid, fd) if records else None

    def cgroup(self, pid, root_fd=None):
        """Map unified membership through a readable cgroup2 mount, or decline.

        Read no global fallback group. In ambiguous namespaces or on cgroup v1,
        report unavailable. Paths are used internally and never printed.
        """
        membership = (self.read(self.root / str(pid) / 'cgroup') if root_fd is None
                      else self.read('cgroup', dir_fd=root_fd))
        mounts = self.read(self.root / 'self' / 'mountinfo', 65536)
        if membership is None or mounts is None:
            return None
        member = next((line[3:] for line in membership.splitlines()
                       if line.startswith('0::')), None)
        if member is None or not member.startswith('/') or '..' in member.split('/'):
            return None
        member = PurePosixPath(member)
        for line in mounts.splitlines()[:512]:
            left, separator, right = line.partition(' - ')
            fields = left.split()
            if not separator or right.split()[:1] != ['cgroup2'] or len(fields) < 5:
                continue
            decode = lambda value: re.sub(r'\\(040|011|012|134)',
                                           lambda m: chr(int(m[1], 8)), value)
            mount_root, mount_point = map(decode, fields[3:5])
            if not mount_root.startswith('/') or '..' in mount_root.split('/'):
                continue
            try:
                relative = member.relative_to(PurePosixPath(mount_root))
                base = Path(mount_point).resolve()
                candidate = (base / str(relative)).resolve()
                candidate.relative_to(base)
            except (OSError, ValueError):
                continue
            return candidate
        return None

    def oom(self, directory=None, dir_fd=None):
        values = {}
        for name in ('memory.events', 'memory.events.local'):
            text = self.read(directory / name) if dir_fd is None else self.read(name, dir_fd=dir_fd)
            if text is None:
                values[name] = None
                continue
            parsed = {}
            for line in text.splitlines():
                fields = line.split()
                if len(fields) == 2 and fields[0] in OOM_KEYS and fields[1].isdecimal():
                    parsed[fields[0]] = int(fields[1])
            values[name] = parsed or None
        return values


class Sampler:
    def __init__(self, pid, reader=None, clock=time.monotonic):
        self.pid = pid
        self.reader = reader or ProcReader()
        self.clock = clock
        self.hz = os.sysconf('SC_CLK_TCK')
        self.page_kib = os.sysconf('SC_PAGE_SIZE') / 1024
        self.previous = {}
        self.previous_at = None
        self.root_identity = None
        self.group = None
        self.group_fd = None
        self.previous_oom = {}

    def sample(self):
        now = self.clock()
        self.reader.unavailable = 0
        self.reader.truncated = False
        records, group = self.reader.inspect(self.pid, self.root_identity)
        if records and self.root_identity is None:
            self.root_identity = identity(records[0])
        current, processes = {}, []
        deltas = []
        for stat in records:
            key = identity(stat)
            current[key] = stat['ticks']
            previous = self.previous.get(key)
            delta = None if previous is None else max(0, stat['ticks'] - previous) / self.hz
            if delta is not None:
                deltas.append(delta)
            processes.append({
                'pid': stat['pid'], 'ppid': stat['ppid'], 'state': stat['state'],
                'cpu_s': round(stat['ticks'] / self.hz, 3),
                'cpu_delta_s': None if delta is None else round(delta, 3),
                'rss_kib_approx': round(stat['rss_pages'] * self.page_kib),
                'threads': stat['threads'], 'sampled_threads': stat['sampled_threads'],
                'thread_states': stat['thread_states'], 'thread_waits': stat['thread_waits'],
                'wait_kinds_omitted': stat['wait_kinds_omitted'],
            })
        if group != self.group:
            self.close()
            self.group_fd = self.reader.open_dir(group) if group is not None else None
        oom = self.reader.oom(dir_fd=self.group_fd) if self.group_fd is not None else None
        oom_delta = None
        if oom is not None and group == self.group:
            oom_delta = {}
            for name, values in oom.items():
                previous = self.previous_oom.get(name)
                oom_delta[name] = None if values is None or previous is None else {
                    key: values[key] - previous[key] for key in values.keys() & previous.keys()
                    if values[key] >= previous[key]
                }
        result = {
            'interval_s': None if self.previous_at is None else round(now - self.previous_at, 3),
            'observed_cpu_delta_s': round(sum(deltas), 3) if deltas else None,
            'tree_rss_kib_approx': (sum(p['rss_kib_approx'] for p in processes)
                                    if processes else None),
            'processes': processes, 'best_effort_tree': True,
            'cgroup_oom_shared_context': oom, 'cgroup_oom_delta': oom_delta,
            'unavailable_reads': self.reader.unavailable, 'truncated': self.reader.truncated,
        }
        self.previous, self.previous_at = current, now
        self.group, self.previous_oom = group, oom or {}
        return result

    def terminal(self):
        """Read the already-pinned cgroup after exit, without a PID lookup."""
        oom = self.reader.oom(dir_fd=self.group_fd) if self.group_fd is not None else None
        delta = None
        if oom is not None:
            delta = {}
            for name, values in oom.items():
                previous = self.previous_oom.get(name)
                delta[name] = None if values is None or previous is None else {
                    key: values[key] - previous[key] for key in values.keys() & previous.keys()
                    if values[key] >= previous[key]
                }
        return {'cgroup_oom_shared_context': oom, 'cgroup_oom_delta': delta}

    def close(self):
        if self.group_fd is not None:
            os.close(self.group_fd)
            self.group_fd = None


def emit(fd, suite, payload):
    """Write a single bounded record; logging failure cannot fail the build."""
    safe_suite = suite if re.fullmatch(r'tests/test_[A-Za-z0-9_]+\.mojo', suite) else 'unlabeled'
    record = {'compiler_telemetry': 1, 'utc': datetime.now(timezone.utc).isoformat(timespec='seconds'),
              'suite': safe_suite[:120], **payload}
    record['processes_omitted_from_log'] = 0
    while True:
        data = (json.dumps(record, separators=(',', ':'), sort_keys=True) + '\n').encode()
        if len(data) <= MAX_LINE:
            break
        if record.get('processes'):
            record['processes'].pop()
            record['processes_omitted_from_log'] += 1
        else:
            return
    try:
        os.write(fd, data)
    except OSError:
        pass


def shell_status(code):
    return 128 - code if code < 0 else code


def run_compiler(command, suite, fd, interval=INTERVAL, sampler_factory=Sampler):
    """Observe while waiting; timeout here schedules samples, never kills work."""
    child = None
    received = []
    pending = []
    sampler = None
    old_handlers = {}

    def send_signal(number):
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, number)
            except OSError:
                pass

    def forward(number, _frame):
        received[:] = [number]
        if child is None:
            pending.append(number)
        else:
            send_signal(number)

    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        old_handlers[number] = signal.signal(number, forward)
    started = time.monotonic()
    try:
        if received:
            return 128 + received[-1]
        # Inherited compiler stdio preserves the surrounding Makefile capture.
        # Its private group lets catchable cancellation reach only this build.
        child = subprocess.Popen(command, start_new_session=True)
        for number in tuple(pending):
            send_signal(number)
        pending.clear()
        try:
            sampler = sampler_factory(child.pid)
        except Exception:
            sampler = None
            emit(fd, suite, {'event': 'telemetry-unavailable'})
        while True:
            if sampler is not None:
                try:
                    emit(fd, suite, {'event': 'sample', **sampler.sample()})
                except Exception:
                    emit(fd, suite, {'event': 'telemetry-unavailable'})
                    try:
                        sampler.close()
                    except Exception:
                        pass
                    sampler = None
            try:
                code = child.wait(timeout=interval if sampler is not None else None)
                break
            except subprocess.TimeoutExpired:
                pass
        status = shell_status(code)
        if received and status == 0:
            status = 128 + received[-1]
        terminal = {}
        if sampler is not None:
            try:
                terminal = sampler.terminal()
            except Exception:
                terminal = {'terminal_telemetry_unavailable': True}
        emit(fd, suite, {'event': 'compiler-exit', 'pid': child.pid, 'exit': status,
                         'elapsed_s': round(time.monotonic() - started, 3), **terminal})
        return status
    finally:
        if sampler is not None:
            try:
                sampler.close()
            except Exception:
                pass
        for number, handler in old_handlers.items():
            signal.signal(number, handler)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--suite', required=True)
    parser.add_argument('--log-fd', type=int, default=3)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('a compiler command is required')
    try:
        if os.environ.get('THREEMOJO_COMPILER_TELEMETRY') != '1' or sys.platform != 'linux':
            os.execvp(command[0], command)
        return run_compiler(command, args.suite, args.log_fd)
    except FileNotFoundError:
        return 127
    except PermissionError:
        return 126


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
