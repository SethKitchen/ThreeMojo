#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Build test-only C dependencies for ordinary and instrumented Mojo suites.

One inventory controls linking, per-suite keys and coverage-tree copies. The
fixtures never enter the production-module denominator. A dependent suite
fails if its fixture/compiler is unavailable; no test is silently skipped.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

FIXTURES = {
    'tests/test_carla_sum2_environment.mojo': ('tools/fixtures/carla_sum2_fp_state.c',),
}
C_FLAGS = ('-std=c11', '-O2', '-fPIC', '-Wall', '-Wextra', '-Werror')


def fixture_inputs(files):
    return sorted({fixture for name in files for fixture in FIXTURES.get(name, ())})


def compiler_identity(cc):
    command = shlex.split(cc)
    if not command:
        raise ValueError('native test compiler command is empty')
    version = subprocess.run([*command, '--version'], check=True, capture_output=True,
                             text=True, timeout=30).stdout
    # A compiler replacement can preserve --version. Bind executable bytes
    # as well so existing fixture/hit-helper objects cannot survive it.
    files = {}
    for index, argument in enumerate(command):
        candidate = Path(argument)
        if not candidate.is_file():
            resolved = shutil.which(argument)
            if resolved is None:
                if index == 0:
                    raise ValueError('native test compiler executable is missing')
                continue
            candidate = Path(resolved)
        candidate = candidate.resolve()
        files[str(candidate)] = hashlib.sha256(candidate.read_bytes()).hexdigest()
    return {'command': command, 'version': version, 'flags': list(C_FLAGS),
            'files': files,
            'system': platform.system(), 'machine': platform.machine()}


def dependency_inputs(root, suite):
    # Reuse the maintained Mojo import resolver, including aggregate runners.
    # The root is the instrumented tree during capture, never the real library.
    import affected
    import suite_key
    root, suite = Path(root).resolve(), Path(suite).resolve()
    relative = suite.relative_to(root).as_posix()
    previous = affected.ROOT
    try:
        affected.ROOT = str(root)
        files = suite_key.closure(relative, set(affected.mojo_files()), {})
    finally:
        affected.ROOT = previous
    return fixture_inputs(files)


def build_object(root, fixture, cache, identity):
    source = Path(root).resolve() / fixture
    data = source.read_bytes()
    inputs = {'source': str(source), 'sha256': hashlib.sha256(data).hexdigest(),
              'compiler': identity}
    key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    cache = Path(cache).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    output, metadata = cache / (key + '.o'), cache / (key + '.json')
    if output.is_file() and metadata.is_file():
        try:
            saved = json.loads(metadata.read_text())
            if (saved.get('inputs') == inputs and saved.get('object_sha256') ==
                    hashlib.sha256(output.read_bytes()).hexdigest()):
                return output
        except (ValueError, OSError):
            pass
    fd, temporary = tempfile.mkstemp(prefix=key + '-', suffix='.o', dir=cache)
    os.close(fd)
    temporary = Path(temporary)
    try:
        command = [*identity['command'], *C_FLAGS, '-c', str(source), '-o', str(temporary)]
        subprocess.run(command, check=True, timeout=120)
        if source.read_bytes() != data:
            raise ValueError('native test fixture changed during compilation: ' + fixture)
        record = {'inputs': inputs, 'command': command,
                  'object_sha256': hashlib.sha256(temporary.read_bytes()).hexdigest()}
        os.replace(temporary, output)
        fd, temporary_meta = tempfile.mkstemp(prefix=key + '-', suffix='.json', dir=cache)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(record, stream, indent=2)
                stream.write('\n')
            os.replace(temporary_meta, metadata)
        finally:
            Path(temporary_meta).unlink(missing_ok=True)
        return output
    finally:
        temporary.unlink(missing_ok=True)


def prepare_command(root, suite, cache, cc, command):
    if not command:
        raise ValueError('a Mojo command is required after --')
    fixtures = dependency_inputs(root, suite)
    if not fixtures:
        return list(command)
    if len(command) < 2 or command[1] != 'build':
        raise ValueError('native fixture object linking requires a Mojo build command')
    source = Path(suite).resolve()
    indices = [index for index, argument in enumerate(command[2:], 2)
               if not argument.startswith('-') and Path(argument).resolve() == source]
    if len(indices) != 1:
        raise ValueError('native fixture suite must occur exactly once in the Mojo command')
    identity = compiler_identity(cc)
    objects = [build_object(root, name, cache, identity) for name in fixtures]
    flags = [argument for path in objects for argument in ('-Xlinker', str(path))]
    index = indices[0]
    return [*command[:index], *flags, *command[index:]]


def prepare_run_commands(root, suite, cache, cc, command, executable):
    """Translate one fixture-dependent run without passing linker flags to JIT.

    Mojo 1.1.0 run and build both default to optimization level 3. Preserve
    explicit compiler options, the copied source and all following program
    arguments. The executable is fresh for this invocation; only C objects
    use the existing content-validated cache.
    """
    if len(command) < 3 or command[1] != 'run':
        raise ValueError('native fixture execution requires a Mojo run command')
    source = Path(suite).resolve()
    indices = [index for index, argument in enumerate(command[2:], 2)
               if not argument.startswith('-') and Path(argument).resolve() == source]
    if not indices:
        raise ValueError('native fixture run is missing its Mojo source')
    # Everything after the first source belongs to the program, even if an
    # argument repeats the source pathname or begins with a compiler flag.
    index = indices[0]
    build = [command[0], 'build', *command[2:index],
             '-o', str(executable), command[index]]
    build = prepare_command(root, suite, cache, cc, build)
    return build, [str(executable), *command[index + 1:]]


class _Cancelled(BaseException):
    def __init__(self, signum):
        self.signum = signum


def run_fixture(root, suite, cache, cc, command, *, program_name=None):
    """Build then execute inside the caller's one supervision/deadline scope.

    Neither stage creates a new process group or receives a separate timeout.
    Coverage owns the enclosing group and its private TMPDIR. Keeping both
    stages in that group lets cancellation stop compiler descendants too.
    """
    previous = {}

    def cancelled(signum, frame):
        raise _Cancelled(signum)

    try:
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous[signum] = signal.signal(signum, cancelled)
        with tempfile.TemporaryDirectory(prefix='threemojo-native-run-',
                                         dir=os.environ.get('TMPDIR') or None) as folder:
            build, execute = prepare_run_commands(
                root, suite, cache, cc, command, Path(folder) / 'suite')
            # Inherit cwd, environment and all streams. Compiler diagnostics
            # and runtime probes pass through the same existing collector.
            status = subprocess.run(build, check=False).returncode
            if status == 0:
                if program_name is None:
                    status = subprocess.run(execute, check=False).returncode
                else:
                    status = subprocess.run([program_name, *execute[1:]],
                                            executable=execute[0], check=False).returncode
            return status if status >= 0 else 128 - status
    except _Cancelled as error:
        return 128 + error.signum
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def copy_fixtures(root, destination):
    root, destination = Path(root).resolve(), Path(destination).resolve()
    for name in fixture_inputs(FIXTURES):
        source, target = root / name, destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if target.read_bytes() != source.read_bytes():
            raise ValueError('native fixture copy changed: ' + name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest='mode', required=True)
    run = commands.add_parser('run')
    run.add_argument('--root', type=Path, required=True)
    run.add_argument('--suite', type=Path, required=True)
    run.add_argument('--cache', type=Path, required=True)
    run.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    run.add_argument('command', nargs=argparse.REMAINDER)
    copy_parser = commands.add_parser('copy')
    copy_parser.add_argument('--root', type=Path, required=True)
    copy_parser.add_argument('--destination', type=Path, required=True)
    fingerprint = commands.add_parser('fingerprint')
    fingerprint.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    args = parser.parse_args(argv)
    try:
        if args.mode == 'copy':
            copy_fixtures(args.root, args.destination)
            return 0
        if args.mode == 'fingerprint':
            print(hashlib.sha256(json.dumps(compiler_identity(args.cc), sort_keys=True).encode()).hexdigest())
            return 0
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        if (len(command) >= 2 and command[1] == 'run'
                and dependency_inputs(args.root, args.suite)):
            return run_fixture(args.root, args.suite, args.cache, args.cc, command)
        prepared = prepare_command(args.root, args.suite, args.cache, args.cc, command)
        # Preserve the original process identity/signal path for the compiler
        # telemetry and coverage collector after fixture preparation finishes.
        os.execvp(prepared[0], prepared)
        raise AssertionError('exec unexpectedly returned')
    except subprocess.CalledProcessError as error:
        print('native test build failed: ' + shlex.join(error.cmd), file=sys.stderr)
        return error.returncode or 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print('native test support failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
