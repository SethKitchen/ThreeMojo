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


def capture(command, out_path, err_path):
    """Run a suite and compress its stderr without changing any probe record."""
    with open(out_path, 'wb') as output, gzip.open(err_path, 'wb', compresslevel=1) as errors:
        with subprocess.Popen(command, stdout=output, stderr=subprocess.PIPE) as process:
            try:
                shutil.copyfileobj(process.stderr, errors, length=1 << 20)
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
