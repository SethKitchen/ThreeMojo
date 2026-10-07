# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Capture exact coverage streams with bounded disk and memory use."""

import argparse
from collections import deque
import gzip
import errno
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time

from test_environment import isolated_environment


LINE = b'COVLINE:'
BRANCH = b'COVBRANCH:'
EVALUATION = b'COVEVAL2:'
MAX_RECORD_BYTES = 512
RECORD_CACHE_CAPACITY = 4096
CACHE_WINDOW_RECORDS = 1024
CACHE_BYPASS_RECORDS = 16384


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


def capture(command, out_path, err_path, *, progress_interval=60):
    """Run a suite and keep what its probe records tell the report, once
    each, compressed; see `Reducer`."""
    if progress_interval <= 0:
        raise ValueError('progress interval must be positive')
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
            with subprocess.Popen(command, stdout=output, stderr=subprocess.PIPE, env=environment) as process:
                try:
                    reducer = Reducer(errors.write)
                    for line in process.stderr:
                        records += 1
                        if first_probe is None and line.lstrip().startswith((LINE, BRANCH, EVALUATION)):
                            first_probe = time.monotonic()
                            progress('first probe')
                        reducer.feed(line)
                    status = process.wait()
                except BaseException:
                    process.kill()
                    process.wait()
                    raise
        progress(f'complete (exit {status})')
        if status:
            print(f'{command[-1]} failed under instrumentation:')
            with open(out_path, errors='replace') as output:
                print(''.join(deque(output, maxlen=30)), end='')
            with gzip.open(err_path, 'rt', errors='replace') as errors:
                print(''.join(deque((line for line in errors if not line.startswith('COV')), maxlen=30)), end='')
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    run = commands.add_parser('capture')
    run.add_argument('--out', type=Path, required=True)
    run.add_argument('--err', type=Path, required=True)
    run.add_argument('command', nargs=argparse.REMAINDER)
    read = commands.add_parser('report')
    read.add_argument('--capture-dir', type=Path, required=True)
    read.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('a command must follow --')
    if args.mode == 'capture':
        return capture(command, args.out, args.err)
    captures = sorted(args.capture_dir.glob('*.txt.gz'))
    if not captures:
        parser.error('no coverage captures were found')
    return report(command, captures)


if __name__ == '__main__':
    sys.exit(main())
