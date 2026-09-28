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


LINE = b'COVLINE:'
BRANCH = b'COVBRANCH:'


class Reducer:
    """Keep what the coverage report reads of a probe stream, once each.

    The report reads two things. Its hit set holds every distinct probe
    payload. Its MC/DC traces hold each decision's distinct evaluations: the
    states its condition records left pending, closed by the decision's own
    record. A suite that runs a probe in a loop repeats both a million
    times, so the raw stream is gigabytes and the report spent most of a CI
    run reading it on one core. This keeps:

    - the first occurrence of each payload, written as a `COVLINE:` record,
      which fills the hit set and which the trace parser skips;
    - each distinct evaluation, when its decision closes, rebuilt as its
      pending condition records and then the decision record.

    So the report sees the same hit set and the same evaluations in the same
    order of first closing, from a few thousand lines. Any other line passes
    through unchanged, for the failure summary. See `coverage/mcdc.mojo`'s
    `TraceParser`, whose reading this follows.
    """

    def __init__(self, write):
        self.write = write
        self.payloads = set()
        self.pending = {}
        self.evaluations = set()

    def feed(self, line):
        """Read one raw line of the stream, and write what it adds."""
        record = line.strip()
        if record.startswith(LINE):
            self._payload(record[len(LINE):])
            return
        if not record.startswith(BRANCH):
            self.write(line)
            return
        payload = record[len(BRANCH):]
        head, colon, state = payload.rpartition(b':')
        base, dot, position = head.rpartition(b'.')
        if not colon or (dot and not position.isdigit()):
            # Malformed: passed as it is, for the report to refuse.
            self.write(line)
            return
        self._payload(payload)
        state = b'T' if state == b'T' else b'F'
        if dot:
            self.pending.setdefault(base, {})[int(position)] = state
            return
        conditions = tuple(sorted(self.pending.pop(head, {}).items()))
        key = (head, conditions, state)
        if key in self.evaluations:
            return
        self.evaluations.add(key)
        for index, value in conditions:
            self.write(BRANCH + head + b'.' + str(index).encode() + b':' + value + b'\n')
        self.write(BRANCH + head + b':' + state + b'\n')

    def _payload(self, payload):
        if payload not in self.payloads:
            self.payloads.add(payload)
            self.write(LINE + payload + b'\n')


def capture(command, out_path, err_path):
    """Run a suite and keep what its probe records tell the report, once
    each, compressed; see `Reducer`."""
    with open(out_path, 'wb') as output, gzip.open(err_path, 'wb', compresslevel=1) as errors:
        with subprocess.Popen(command, stdout=output, stderr=subprocess.PIPE) as process:
            try:
                reducer = Reducer(errors.write)
                for line in process.stderr:
                    reducer.feed(line)
                status = process.wait()
            except BaseException:
                process.kill()
                process.wait()
                raise
    if status:
        print(f'{command[-1]} failed under instrumentation:')
        with open(out_path, errors='replace') as output:
            print(''.join(deque(output, maxlen=30)), end='')
        with gzip.open(err_path, 'rt', errors='replace') as errors:
            print(''.join(deque((line for line in errors if not line.startswith('COV')), maxlen=30)), end='')
    return status if status >= 0 else 128 - status


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
