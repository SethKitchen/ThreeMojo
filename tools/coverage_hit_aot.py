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
import os
from pathlib import Path
import platform
import stat

import native_test_support as native

ROOT = Path(__file__).resolve().parent.parent
HELPER = 'tools/coverage_hit_cache.c'


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


def main(argv=None):
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
    prepared, name = prepare_profile(args.root, args.suite, args.cache, args.cc,
                                     command, args.profile)
    return native.run_fixture(args.root, args.suite, args.cache, args.cc,
                              prepared, program_name=name)


if __name__ == '__main__':
    raise SystemExit(main())
