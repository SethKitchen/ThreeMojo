#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Run an explicit raw, compiled, or compiled exact-hit coverage profile.

This prototype preserves the source argument as argv[0], trailing arguments,
cwd, environment and the supervisor's total deadline. The process executable
is a temporary native binary in compiled profiles; that identity deliberately
differs from the Mojo JIT. Raw/JIT mode keeps its original command unchanged.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shlex
import stat
import sys
import time

import native_test_support as native

ROOT = Path(__file__).resolve().parent.parent
HELPER = 'tools/coverage_hit_cache.c'


PHASE_ENV = 'THREEMOJO_COVERAGE_PHASES'
PHASE_SCHEMA = 'coverage-exec-phases-v1'
PHASE_MAX_BYTES = 128 * 1024
PHASE_MAX_RECORD = 16 * 1024
PHASE_MAX_EVENTS = 32


class _PhaseObserver:
    """Observe requests in this one adapter process, never child completion.

    No stream redirection, subprocess wrapper, environment dump or child PID
    is involved. The non-inheritable descriptor belongs only to this adapter.
    An absent finish or diagnostics_complete=false means diagnostic loss.
    """

    def __init__(self, suite, command, cc='cc'):
        self.descriptor = None
        self.suite = suite.stem
        self.mojo = command[0]
        self.source = None
        self.size = 0
        self.events = 0
        self.complete = True
        self.build_requested = False
        try:
            self.cc = shlex.split(cc)
            self.source = command[source_index(command, suite)]
            path = os.environ[PHASE_ENV]
            descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NONBLOCK | os.O_NOFOLLOW)
            self.descriptor = descriptor
            os.set_inheritable(descriptor, False)
            actual = os.fstat(descriptor)
            expected = (int(os.environ[PHASE_ENV + '_DEVICE']),
                        int(os.environ[PHASE_ENV + '_INODE']))
            if not stat.S_ISREG(actual.st_mode) or (actual.st_dev, actual.st_ino) != expected:
                raise ValueError('phase file identity changed')
            self.size = actual.st_size
        except Exception:
            self.complete = False
            self.close()

    def _write(self, phase, **fields):
        if self.descriptor is None:
            return
        record = {'schema': PHASE_SCHEMA, 'suite': self.suite,
                  'utc': datetime.now(timezone.utc).isoformat(),
                  'monotonic': time.monotonic(), 'adapter_pid': os.getpid(),
                  'phase': phase, **fields}
        data = (json.dumps(record, ensure_ascii=True) + '\n').encode()
        if len(data) > PHASE_MAX_RECORD or self.size + len(data) > PHASE_MAX_BYTES:
            raise ValueError('phase record size limit')
        written = os.write(self.descriptor, data)
        self.size += written
        if written != len(data):
            raise OSError('short phase write')

    def _lost(self, error):
        self.complete = False
        try:
            self._write('diagnostics_incomplete', exception=type(error).__name__)
        except Exception:
            # The parent's header and missing finish still expose the loss.
            self.close()

    def audit(self, event, arguments):
        if event != 'subprocess.Popen' or self.descriptor is None or not self.complete:
            return
        try:
            executable, argv, _cwd, _environment = arguments
            self.events += 1
            if self.events > PHASE_MAX_EVENTS:
                raise ValueError('phase event limit')
            executable = os.fsdecode(executable)
            argv = [os.fsdecode(argument) for argument in argv]
            if (not self.build_requested and len(argv) > 1
                    and argv[:2] == [self.mojo, 'build'] and argv[-1] == self.source):
                phase = 'mojo_build_launch_request'
                self.build_requested = True
                fields = {}
            elif self.build_requested and argv and argv[0] == self.source:
                # Preserve the executable override and source argv0. Arbitrary
                # program arguments are private, outside the sealed suite run.
                phase = 'native_runtime_launch_request'
                fields = {'omitted_program_arguments': len(argv) - 1}
                argv = argv[:1]
            elif not self.build_requested and self._helper_command(argv):
                phase = 'native_helper_launch_request'
                fields = {}
            else:
                raise ValueError('unrecognized subprocess request')
            self._write(phase, executable=executable, argv=argv, **fields)
        except Exception as error:
            self._lost(error)

    def _helper_command(self, argv):
        if not self.cc or argv[:len(self.cc)] != self.cc:
            return False
        tail = argv[len(self.cc):]
        if tail[:1] == ['-pthread']:
            tail = tail[1:]
        flags = list(native.C_FLAGS)
        return (tail == ['--version'] or
                len(tail) == len(flags) + 4 and tail[:len(flags)] == flags
                and tail[len(flags)] == '-c' and tail[-2] == '-o')

    def finish(self, **outcome):
        # Another audit hook can silently refuse registration. A compiled
        # adapter with no observed requests cannot claim a complete trace.
        if not self.events and self.complete:
            self._lost(RuntimeError('no subprocess requests observed'))
        try:
            self._write('adapter_finish', diagnostics_complete=self.complete, **outcome)
        except Exception as error:
            self._lost(error)
        finally:
            self.close()

    def close(self):
        descriptor, self.descriptor = self.descriptor, None
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass


def source_index(command, suite):
    if len(command) < 3 or command[1] != 'run':
        raise ValueError('coverage profile requires a Mojo run command')
    source = Path(suite).resolve()
    for index, argument in enumerate(command[2:], 2):
        if not argument.startswith('-') and Path(argument).resolve() == source:
            return index
    raise ValueError('coverage profile is missing its source argument')


def prepare_profile(root, suite, cache, cc, command, profile):
    if profile == 'raw':
        return list(command), None
    index = source_index(command, suite)
    prepared = list(command)
    if profile == 'aot-hits':
        if platform.system() != 'Linux':
            raise ValueError('private hit profile currently supports Linux only')
        sink = os.fstat(2)
        if not stat.S_ISFIFO(sink.st_mode):
            raise ValueError('private hit profile requires a supervised capture pipe')
        # Set only this child process's environment. The constructor runs before
        # the native suite and verifies this original capture identity.
        os.environ['THREEMOJO_COVERAGE_PIPE_DEVICE'] = str(sink.st_dev)
        os.environ['THREEMOJO_COVERAGE_PIPE_INODE'] = str(sink.st_ino)
        identity = native.compiler_identity(cc + ' -pthread')
        obj = native.build_object(ROOT, HELPER, cache, identity)
        prepared[index:index] = ['-DTHREEMOJO_COVERAGE_HIT_CACHE', '-Xlinker', str(obj)]
    return prepared, command[index]


def main(argv=None, *, _observe=False):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--profile', choices=('raw', 'aot', 'aot-hits'), required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--suite', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('a Mojo command is required after --')
    if args.profile == 'raw':
        # Retain the qualified fixture-specific repair for raw captures.
        if native.dependency_inputs(args.root, args.suite):
            return native.run_fixture(args.root, args.suite, args.cache, args.cc, command)
        os.execvp(command[0], command)
    # Only the single-use CLI installs a hook. Importing/calling this module
    # as a library leaves the process's permanent audit-hook list untouched.
    observer = None
    if _observe and PHASE_ENV in os.environ:
        observer = _PhaseObserver(args.suite, command, args.cc)
        for key in (PHASE_ENV, PHASE_ENV + '_DEVICE', PHASE_ENV + '_INODE'):
            os.environ.pop(key, None)
        if observer.descriptor is not None:
            try:
                sys.addaudithook(observer.audit)
            except Exception as error:
                observer._lost(error)
    try:
        prepared, name = prepare_profile(args.root, args.suite, args.cache, args.cc,
                                         command, args.profile)
        status = native.run_fixture(args.root, args.suite, args.cache, args.cc,
                                    prepared, program_name=name)
    except BaseException as error:
        if observer is not None:
            observer.finish(exception=type(error).__name__)
        raise
    else:
        if observer is not None:
            observer.finish(status=status)
        return status


if __name__ == '__main__':
    raise SystemExit(main(_observe=True))
