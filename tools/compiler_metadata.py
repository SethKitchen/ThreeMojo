# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Record bounded compiler identity/target metadata; never compile a source.

Run with the compiler's virtual-environment Python. Diagnostic errors are
reported as unavailable and do not replace or relax the following CPU check.
Only selected version/target fields and executable hashes are logged.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import threading
import time

from coverage_process_group import kill_owned_group

MAX_OUTPUT = 8192
MAX_BINARY = 512 * 1024 * 1024
TIMEOUT = 10.0
TOTAL_TIMEOUT = 30.0
TARGET_FIELDS = {'target-triple', 'target-cpu', 'target-features',
                 'target-accelerator', 'target-abi'}
BUILD_ARGS = ['-I', '.', '--num-threads', '1',
              '--target-triple=x86_64-unknown-linux-gnu', '--target-cpu=x86-64-v3',
              '--Werror',
              '-o', '.cache/bin/test_exact_predicates', 'tests/test_exact_predicates.mojo']

_REAP_STATE = threading.local()


class _ReapGuard:
    def __init__(self):
        self.active = False
        self.pending = None

    def deliver(self, error):
        if self.active:
            if self.pending is None:
                self.pending = error
        else:
            raise error


def read_command(command, timeout=TIMEOUT, limit=MAX_OUTPUT):
    """Read at most limit bytes; stop only the owned metadata process on error."""
    child = None
    reaped = False
    can_signal = False
    reap_error = None

    def wait_owned(timeout):
        nonlocal can_signal, reaped, reap_error
        deadline = time.monotonic() + timeout
        while True:
            # main's stable callbacks defer only across a nonblocking reap
            # and ownership update. Thread-local signal masking alone cannot
            # prevent Python callbacks delivered through another thread.
            guard = getattr(_REAP_STATE, 'guard', None)
            was_guarded = guard.active if guard is not None else False
            if guard is not None:
                guard.active = True
            was_owned = can_signal
            can_signal = False
            try:
                try:
                    code = child.wait(timeout=0)
                except subprocess.TimeoutExpired:
                    can_signal = was_owned
                except BaseException as error:
                    reap_error = error
                    raise
                else:
                    reaped = True
                    return code
            finally:
                if guard is not None:
                    guard.active = was_guarded
                    if not was_guarded and guard.pending is not None:
                        error, guard.pending = guard.pending, None
                        raise error
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(command, timeout)
            time.sleep(min(0.01, remaining))

    try:
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
        can_signal = True
        data = bytearray()
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None, 'timeout'
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fileobj.fileno(), min(4096, limit + 1 - len(data)))
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        data.extend(chunk)
                        if len(data) > limit:
                            return None, 'output-limit'
            try:
                code = wait_owned(timeout=max(0.001, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                return None, 'timeout'
        return (data.decode('ascii', 'replace'), 'ok') if code == 0 else (None, 'failed')
    except OSError:
        if reap_error is not None:
            raise
        return None, 'unavailable'
    finally:
        if child is not None:
            try:
                if not reaped and can_signal:
                    # No poll/wait has reaped this PID on an early return, so its
                    # owned group cannot be confused with a reused PID/group.
                    kill_owned_group(child, reap=wait_owned)
                    try:
                        wait_owned(timeout=1.0)
                    except subprocess.TimeoutExpired:
                        raise MetadataDeadline()
            finally:
                if child.stdout is not None:
                    child.stdout.close()


def file_identity(path):
    """Hash only the selected executable, with a finite read bound."""
    try:
        path = Path(path)
        size = path.stat().st_size
        if size > MAX_BINARY or not path.is_file():
            return {'status': 'unavailable'}
        digest = hashlib.sha256()
        read = 0
        with path.open('rb') as stream:
            while True:
                part = stream.read(min(1024 * 1024, MAX_BINARY + 1 - read))
                if not part:
                    break
                read += len(part)
                if read > MAX_BINARY:
                    return {'status': 'unavailable'}
                digest.update(part)
        if read != size:
            return {'status': 'changed-during-read'}
        return {'status': 'ok', 'sha256': digest.hexdigest(), 'bytes': read}
    except (OSError, TypeError):
        return {'status': 'unavailable'}


def active_driver(compiler):
    """Use the pinned wheel launcher's own resolution without logging its env."""
    expected = Path(sys.executable).parent / 'mojo'
    if not Path(compiler).samefile(expected):
        raise ValueError('compiler and metadata interpreter differ')
    from mojo.run import _mojo_env
    return _mojo_env()['MODULAR_MOJO_MAX_DRIVER_PATH']


def collect(compiler, run=read_command, resolve_driver=None):
    result = {'compiler_metadata': 1, 'launcher': file_identity(compiler)}
    try:
        result['driver'] = file_identity(active_driver(compiler) if resolve_driver is None
                                          else resolve_driver())
    except Exception:
        result['driver'] = {'status': 'unavailable'}
    version, status = run([compiler, '--version'])
    lines = [] if version is None else version.splitlines()
    result['version_status'] = status
    if len(lines) == 1 and re.fullmatch(r'Mojo [A-Za-z0-9. ()+_-]{1,80}', lines[0]):
        result['version'] = lines[0]
    elif status == 'ok':
        result['version_status'] = 'unrecognized-output'
    # --print-effective-target exits after flag resolution, before compilation.
    command = [compiler, 'build', '--print-effective-target', *BUILD_ARGS]
    target, status = run(command)
    result['target_status'] = status
    result['target_command'] = command
    if target is not None:
        fields = {}
        valid = target.splitlines()[:1] == ['Effective target configuration:']
        for line in target.splitlines()[1:]:
            match = re.fullmatch(r'  --([a-z-]+) ([A-Za-z0-9_+.,:-]+)', line)
            if match and match[1] in TARGET_FIELDS and match[1] not in fields:
                fields[match[1]] = match[2]
            elif line.strip():
                valid = False
        if valid and {'target-triple', 'target-cpu', 'target-features'} <= fields.keys():
            result['effective_target'] = fields
        else:
            result['target_status'] = 'unrecognized-output'
    return result


class MetadataDeadline(BaseException):
    pass


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--compiler', default='.venv/bin/mojo')
    args = parser.parse_args(argv)
    guard = _ReapGuard()
    previous_guard = getattr(_REAP_STATE, 'guard', None)

    def expired(_number, _frame):
        guard.deliver(MetadataDeadline())

    def cancelled(number, _frame):
        # Unwind read_command's cleanup before leaving this metadata process.
        guard.deliver(SystemExit(128 + number))

    handlers = {number: signal.getsignal(number) for number in
                (signal.SIGALRM, signal.SIGINT, signal.SIGTERM)}
    previous_timer = signal.getitimer(signal.ITIMER_REAL)
    _REAP_STATE.guard = guard
    signal.signal(signal.SIGALRM, expired)
    signal.signal(signal.SIGINT, cancelled)
    signal.signal(signal.SIGTERM, cancelled)
    signal.setitimer(signal.ITIMER_REAL, TOTAL_TIMEOUT)
    try:
        try:
            result = collect(args.compiler)
            encoded = json.dumps(result, separators=(',', ':'), sort_keys=True)
            if len(encoded.encode()) > MAX_OUTPUT:
                result = {'compiler_metadata': 1, 'status': 'record-limit'}
        except (Exception, MetadataDeadline):
            result = {'compiler_metadata': 1, 'status': 'unavailable'}
    finally:
        _REAP_STATE.guard = previous_guard
        signal.setitimer(signal.ITIMER_REAL, 0)
        for number, handler in handlers.items():
            signal.signal(number, handler)
        signal.setitimer(signal.ITIMER_REAL, *previous_timer)
    print(json.dumps(result, separators=(',', ':'), sort_keys=True), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
