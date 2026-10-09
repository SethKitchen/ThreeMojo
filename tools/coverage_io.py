# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Capture exact coverage streams with bounded disk and memory use."""

import argparse
from collections import deque
import gzip
import errno
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

from coverage_process_group import kill_owned_group
from test_environment import isolated_environment
import coverage_loop_proofs

ACTIVE_SOURCE_SHA256 = coverage_loop_proofs.file_sha256(Path(__file__))


def _check_proof_consumer(proof):
    if proof['receipt']['root_inputs'].get('tools/coverage_io.py') != ACTIVE_SOURCE_SHA256:
        raise ValueError('Stale or modified executing capture/report wrapper')


LINE = b'COVLINE:'
BRANCH = b'COVBRANCH:'
EVALUATION = b'COVEVAL2:'
MAX_RECORD_BYTES = 512
RECORD_CACHE_CAPACITY = 4096
CACHE_WINDOW_RECORDS = 1024
CACHE_BYPASS_RECORDS = 16384
DEADLINE_ENV = 'THREEMOJO_COVERAGE_DEADLINE'


def shared_deadline():
    """Read the group's absolute clock deadline, never a fresh suite budget."""
    value = os.environ.get(DEADLINE_ENV)
    if value is None:
        return None
    deadline = float(value)
    if not math.isfinite(deadline):
        raise ValueError('coverage deadline must be finite')
    return deadline


def group(command, seconds):
    """Give xargs and every capture one deadline, including queued suites."""
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('coverage budget must be positive and finite')
    deadline = time.monotonic() + seconds
    inherited = shared_deadline()
    if inherited is not None:
        deadline = min(deadline, inherited)
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return 124
    environment = os.environ.copy()
    environment[DEADLINE_ENV] = repr(deadline)
    # The alarm stops xargs scheduling. Captures independently enforce this
    # same deadline and clean up their owned groups even after xargs exits.
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.setitimer(signal.ITIMER_REAL, remaining)
    os.execvpe(command[0], command, environment)
    raise AssertionError('exec unexpectedly returned')


class _CaptureProcess:
    """Own the adapter and all its build/run descendants until capture ends."""

    def __init__(self, command, output, environment, deadline):
        self.command, self.output = command, output
        self.environment, self.deadline = environment, deadline
        self.child = None
        self.active = False
        self.group_signal_complete = False
        self.cleanup_error = None
        self.killing = False
        self.cancelled_status = None
        self.lock = threading.RLock()
        self.stopped = threading.Event()
        self.watchdog = None
        self.handlers = {}

    def _kill(self):
        # Python signal handlers can reenter this method despite the RLock.
        # A nested cleanup must not reap between the active check and signal.
        if self.killing:
            return
        self.killing = True
        try:
            self._kill_owned()
        finally:
            self.killing = False

    def _kill_owned(self):
        if self.cleanup_error is not None:
            raise self.cleanup_error
        if self.active and not self.group_signal_complete:
            try:
                kill_owned_group(self.child, reap=self._reap)
                # The group dispatch succeeded or the group is confirmed absent.
                # Keep ownership until reaping, but do not signal again while
                # those processes exit. A failed dispatch never sets this flag.
                self.group_signal_complete = True
            except BaseException as error:
                # Reaped/uncertain ownership must stay disarmed even when
                # the helper's later probe fails or a signal interrupts it.
                if not self.active:
                    self.cleanup_error = error
                raise

    def _reap(self, timeout=None):
        if self.cleanup_error is not None:
            raise self.cleanup_error
        # The caller holds the lock against the watchdog. Disarm first also
        # covers a Python signal handler between kernel reaping and return.
        was_active = self.active
        self.active = False
        try:
            return self.child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.active = was_active
            raise
        except BaseException as error:
            # An interrupted/failed reap has uncertain ownership. Keep it
            # disarmed and preserve the failure on later cancellation/exit.
            self.cleanup_error = error
            raise

    def cancel(self, status):
        with self.lock:
            if self.cancelled_status is None:
                self.cancelled_status = status
            self._kill()

    def _signal(self, number, _frame):
        self.cancel(128 + number)

    def _deadline(self):
        if not self.stopped.wait(max(0, self.deadline - time.monotonic())):
            self.cancel(124)

    def __enter__(self):
        try:
            for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                self.handlers[number] = signal.signal(number, self._signal)
            with self.lock:
                if self.deadline is not None and time.monotonic() >= self.deadline:
                    self.cancelled_status = 124
                if self.cancelled_status is None:
                    self.child = subprocess.Popen(
                        self.command, stdout=self.output, stderr=subprocess.PIPE,
                        env=self.environment, start_new_session=True)
                    self.active = True
                    # A signal may have arrived before Popen assigned the child.
                    if self.cancelled_status is not None:
                        self._kill()
            if self.child is not None and self.deadline is not None:
                self.watchdog = threading.Thread(target=self._deadline, daemon=True)
                self.watchdog.start()
            return self
        except BaseException:
            self.__exit__(*sys.exc_info())
            raise

    def wait(self):
        if self.child is None:
            return self.cancelled_status
        while True:
            # Reaping and disabling group signals share a lock: the watchdog
            # cannot target a PID after wait has made it available for reuse.
            with self.lock:
                try:
                    status = self._reap(timeout=0)
                except subprocess.TimeoutExpired:
                    # A handler may have recorded cancellation while reaping
                    # was disarmed. Retry the signal only while still owned.
                    if self.cancelled_status is not None:
                        self._kill()
                else:
                    return self.cancelled_status if self.cancelled_status is not None else status
            # Never hold or repeatedly reacquire the lock while waiting: the
            # watchdog needs it even when a child closes stderr before exit.
            self.stopped.wait(0.01)

    def __exit__(self, *_error):
        self.stopped.set()
        if self.watchdog is not None and self.watchdog.ident is not None:
            self.watchdog.join()
        try:
            with self.lock:
                self._kill()
                if self.child is not None:
                    self._reap()
                    self.child.stderr.close()
        finally:
            for number, handler in self.handlers.items():
                signal.signal(number, handler)


class _EvidenceReducer:
    """Keep distinct hits and complete version 2 evaluation records.

    Completed vectors are assembled inside each function invocation, so the
    reducer needs no pending operands or inference about evaluation boundaries.
    Legacy compound records must be recaptured; they cannot certify MC/DC.
    """

    def __init__(self, write):
        self.write = write
        self.payloads = set()
        self.evaluations = set()

    def feed(self, line):
        """Read one raw line; reject malformed or ambiguous probe records."""
        record = line.strip()
        if record.startswith(LINE):
            self._payload(record[len(LINE):])
            return
        if record.startswith(EVALUATION):
            if len(record) + 1 > MAX_RECORD_BYTES or not record.endswith(b';') or not line.endswith(b'\n'):
                raise ValueError(f'Malformed or truncated evaluation record: {record!r}')
            head, colon, vector = record[len(EVALUATION):-1].rpartition(b':')
            decision, separator, outcome = head.rpartition(b':')
            module, delimiter, number = decision.rpartition(b':')
            if not separator or outcome not in (b'T', b'F'):
                raise ValueError(f'Malformed evaluation outcome: {record!r}')
            if not delimiter or not module or not number.isdigit() or int(number) < 1:
                raise ValueError(f'Malformed evaluation decision ID: {record!r}')
            if not colon or len(vector) < 2 or any(value not in b'TF-' for value in vector) or not set(vector) & set(b'TF'):
                raise ValueError(f'Malformed evaluation vector: {record!r}')
            key = (decision, vector, outcome)
            if key not in self.evaluations:
                self.evaluations.add(key)
                self.write(record + b'\n')
            return
        if not record.startswith(BRANCH):
            self.write(line)
            return
        payload = record[len(BRANCH):]
        head, colon, state = payload.rpartition(b':')
        if colon and state not in (b'T', b'F'):
            raise ValueError(f'Malformed branch outcome: {record!r}')
        if not colon:
            self.write(line)
            return
        if b'.' in head:
            raise ValueError('Legacy compound coverage is ambiguous; recapture with protocol 2')
        module, delimiter, number = head.rpartition(b':')
        if not delimiter or not module or not number.isdigit() or int(number) < 1:
            raise ValueError(f'Malformed branch decision ID: {record!r}')
        self._payload(payload)
        key = (head, b'', state)
        if key not in self.evaluations:
            self.evaluations.add(key)
            self.write(record + b'\n')

    def _payload(self, payload):
        if payload not in self.payloads:
            self.payloads.add(payload)
            self.write(LINE + payload + b'\n')



class Reducer(_EvidenceReducer):
    """Cache accepted raw records only while a bounded sample finds reuse."""

    def __init__(self, write):
        super().__init__(write)
        self._accepted_records = set()
        self._remaining = CACHE_WINDOW_RECORDS
        self._hits = 0
        self._bypassing = False

    def feed(self, line):
        if self._remaining == 0:
            self._next_window()
        self._remaining -= 1
        if self._bypassing:
            _EvidenceReducer.feed(self, line)
            return
        if isinstance(line, bytes) and line in self._accepted_records:
            self._hits += 1
            return
        _EvidenceReducer.feed(self, line)
        self._remember(line)

    def _next_window(self):
        # Retain caching only with at least 25% exact hits in the last window.
        # A bounded bypass avoids repeated admission on cold/churning input.
        # Then sample again, so a later hot phase can recover automatically.
        if self._bypassing:
            self._bypassing = False
            self._remaining = CACHE_WINDOW_RECORDS
        elif self._hits * 4 < CACHE_WINDOW_RECORDS:
            self._accepted_records.clear()
            self._bypassing = True
            self._remaining = CACHE_BYPASS_RECORDS
        else:
            self._remaining = CACHE_WINDOW_RECORDS
        self._hits = 0

    def _remember(self, line):
        # Called only after the original parser and every write succeeded.
        # Bound both count and raw byte length, including any whitespace.
        if not isinstance(line, bytes) or len(line) > MAX_RECORD_BYTES or not line.endswith(b'\n'):
            return
        record = line.strip()
        if not (record.startswith((LINE, EVALUATION)) or
                record.startswith(BRANCH) and b':' in record[len(BRANCH):]):
            # COVBRANCH without a payload colon is diagnostic passthrough.
            return
        if len(self._accepted_records) >= RECORD_CACHE_CAPACITY:
            self._accepted_records.clear()
        self._accepted_records.add(line)


def capture(command, out_path, err_path, *, progress_interval=60, loop_proof=None,
            source_root=None):
    """Run a suite and keep what its probe records tell the report, once
    each, compressed; see `Reducer`."""
    if progress_interval <= 0:
        raise ValueError('progress interval must be positive')
    proof = None
    if loop_proof is not None:
        # A failed replacement capture must never retain an old success receipt.
        coverage_loop_proofs.capture_receipt_path(err_path).unlink(missing_ok=True)
        proof = coverage_loop_proofs.read_receipt(loop_proof)
        _check_proof_consumer(proof)
        proof_root = Path(source_root) if source_root is not None else Path(__file__).resolve().parent.parent
        proof_build = Path(loop_proof).resolve().parent
        coverage_loop_proofs.check_capture_inputs(proof, proof_root, proof_build)
        coverage_loop_proofs.validate_capture_command(
            command, proof, proof_root, proof_build, err_path, out_path)
    deadline = shared_deadline()
    suite = Path(out_path).stem
    started = time.monotonic()
    stopped = threading.Event()
    records = 0
    first_probe = None

    def progress(stage):
        elapsed = time.monotonic() - started
        phase = 'waiting for probes (compile/startup)' if first_probe is None else 'runtime probes observed'
        print(f'Coverage {suite}: {stage}; {elapsed:.1f}s; {phase}; '
              f'{records} stderr records', flush=True)

    def heartbeat():
        while not stopped.wait(progress_interval):
            progress('running')

    progress('start')
    monitor = threading.Thread(target=heartbeat, daemon=True)
    monitor.start()
    try:
        with isolated_environment() as environment, open(out_path, 'wb') as output, gzip.open(err_path, 'wb', compresslevel=1) as errors:
            with _CaptureProcess(command, output, environment, deadline) as process:
                try:
                    reducer = Reducer(errors.write)
                    for line in (() if process.child is None else process.child.stderr):
                        records += 1
                        if first_probe is None and line.lstrip().startswith((LINE, BRANCH, EVALUATION)):
                            first_probe = time.monotonic()
                            progress('first probe')
                        reducer.feed(line)
                    status = process.wait()
                except BaseException:
                    if process.cancelled_status is None:
                        raise
                    status = process.cancelled_status
        progress(f'complete (exit {status})')
        if status:
            print(f'{command[-1]} failed under instrumentation:')
            with open(out_path, errors='replace') as output:
                print(''.join(deque(output, maxlen=30)), end='')
            with gzip.open(err_path, 'rt', errors='replace') as errors:
                print(''.join(deque((line for line in errors if not line.startswith('COV')), maxlen=30)), end='')
        elif proof is not None:
            if coverage_loop_proofs.read_receipt(loop_proof) != proof:
                raise ValueError('Loop-proof binding changed during capture')
            coverage_loop_proofs.check_capture_inputs(proof, proof_root, proof_build)
            coverage_loop_proofs.bind_capture(err_path, out_path, proof, command,
                                              root=proof_root, build=proof_build)
        return status if status >= 0 else 128 - status
    except BaseException:
        progress('aborted')
        raise
    finally:
        stopped.set()
        monitor.join()


def report(command, captures):
    """Replay each complete stream through a FIFO, in the original order.

    The Mojo reporter reads one stream at a time. One writer thread follows
    that same order, so decompressed captures never occupy disk. Failure in
    either process terminates the replay instead of leaving an open reader.
    """
    with tempfile.TemporaryDirectory(prefix='threemojo-coverage-') as directory:
        pipes = [Path(directory) / str(index) for index in range(len(captures))]
        for pipe in pipes:
            os.mkfifo(pipe)
        process = subprocess.Popen([*command, *(str(pipe) for pipe in pipes)])
        failures = []

        def replay():
            try:
                for source, pipe in zip(captures, pipes):
                    while process.poll() is None:
                        try:
                            descriptor = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
                            break
                        except OSError as error:
                            if error.errno != errno.ENXIO:
                                raise
                            time.sleep(0.01)
                    else:
                        return
                    os.set_blocking(descriptor, True)
                    with gzip.open(source, 'rb') as incoming, os.fdopen(descriptor, 'wb') as outgoing:
                        shutil.copyfileobj(incoming, outgoing, length=1 << 20)
            except BaseException as error:
                failures.append(error)
                process.terminate()

        writer = threading.Thread(target=replay, daemon=True)
        writer.start()
        try:
            status = process.wait()
        except BaseException:
            process.kill()
            process.wait()
            raise
        writer.join(timeout=1)
        if failures:
            print(f'Coverage replay failed: {failures[0]}', file=sys.stderr)
            return 1
        return status if status >= 0 else 128 - status


def report_with_loop_proofs(command, captures, *, root, build, compiler, flags,
                            mojo=None, capture_cache=None, suites=None):
    """Validate source/tool/capture bindings before applying outcome masks."""
    build = Path(build)
    original = build / 'manifest.txt'
    if not command or Path(command[-1]).resolve() != original.resolve():
        raise ValueError('The report command must end with the original manifest')
    proof_path = build / 'loop-proofs.json'
    settings = {'mojo': mojo, 'capture_cache': capture_cache, 'suites': suites}
    proof = coverage_loop_proofs.verify(proof_path, root, build, compiler, flags, **settings)
    _check_proof_consumer(proof)
    coverage_loop_proofs.verify_captures(captures, proof)
    derived = coverage_loop_proofs.masked_manifest(original.read_bytes(), proof)
    with tempfile.TemporaryDirectory(prefix='threemojo-loop-report-') as directory:
        manifest = Path(directory) / 'manifest.txt'
        manifest.write_bytes(derived)
        print('Validated loop-proof binding ' + proof['sha256'], flush=True)
        status = report([*command[:-1], str(manifest)], captures)
        # Concurrent changes must not turn a stale report into a passing gate.
        final_proof = coverage_loop_proofs.verify(proof_path, root, build, compiler, flags, **settings)
        if final_proof != proof:
            raise ValueError('Loop-proof identity changed during reporting')
        coverage_loop_proofs.verify_captures(captures, proof)
        return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    grouped = commands.add_parser('group')
    grouped.add_argument('--seconds', type=float, required=True)
    grouped.add_argument('command', nargs=argparse.REMAINDER)
    run = commands.add_parser('capture')
    run.add_argument('--out', type=Path, required=True)
    run.add_argument('--err', type=Path, required=True)
    run.add_argument('--loop-proof', type=Path)
    run.add_argument('--loop-proof-root', type=Path)
    run.add_argument('command', nargs=argparse.REMAINDER)
    read = commands.add_parser('report')
    read.add_argument('--capture-dir', type=Path, required=True)
    read.add_argument('--loop-proof-root', type=Path)
    read.add_argument('--loop-proof-build', type=Path)
    read.add_argument('--compiler', default='')
    read.add_argument('--flags', default='')
    read.add_argument('--mojo')
    read.add_argument('--capture-cache')
    read.add_argument('--suites', nargs='*')
    read.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('a command must follow --')
    if args.mode == 'group':
        return group(command, args.seconds)
    if args.mode == 'capture':
        return capture(command, args.out, args.err, loop_proof=args.loop_proof,
                       source_root=args.loop_proof_root)
    captures = sorted(args.capture_dir.glob('*.txt.gz'))
    if not captures:
        parser.error('no coverage captures were found')
    if args.loop_proof_root is not None or args.loop_proof_build is not None:
        if args.loop_proof_root is None or args.loop_proof_build is None:
            parser.error('both loop-proof root and build are required')
        return report_with_loop_proofs(command, captures, root=args.loop_proof_root,
                                      build=args.loop_proof_build,
                                      compiler=args.compiler, flags=args.flags,
                                      mojo=args.mojo, capture_cache=args.capture_cache,
                                      suites=args.suites)
    return report(command, captures)


if __name__ == '__main__':
    sys.exit(main())
