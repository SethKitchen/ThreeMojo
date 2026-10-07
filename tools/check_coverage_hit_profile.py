# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check phase, argv and complete-vector contracts of compiled coverage.

Every native test keeps its five-second limit. Raw protocol checks remain in
check_coverage_protocol.py; the Linux private profile additionally checks the
exact transport implementation with deterministic syscall faults.
"""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

from run_suite import result_errors, slow_tests

ROOT = Path(__file__).resolve().parent.parent
PROBE = r'''from std.testing import TestSuite
from coverage.runtime import hit, begin, leaf, finish
from std.testing import assert_equal


struct PhaseValue(ImplicitlyCopyable):
    var value: Int

    def __init__(out self, compile_phase: Bool):
        hit(
            StaticString(
                "compile:constructor"
            ) if compile_phase else StaticString("runtime:constructor")
        )
        var values = List[Int]()
        _ = begin(values, 2)
        _ = leaf(
            True,
            values,
            StaticString(
                "compile:decision.0"
            ) if compile_phase else StaticString("runtime:decision.0"),
            0,
        )
        _ = leaf(
            False,
            values,
            StaticString(
                "compile:decision.1"
            ) if compile_phase else StaticString("runtime:decision.1"),
            1,
        )
        _ = finish(
            False,
            values,
            StaticString("compile:decision") if compile_phase else StaticString(
                "runtime:decision"
            ),
        )
        self.value = 7


comptime VALUE = PhaseValue(True)


def test_phase() raises:
    assert_equal(VALUE.value, 7)
    var runtime = PhaseValue(False)
    assert_equal(runtime.value, 7)
    print("phase done")

from coverage.runtime import hit, branch, _emit, begin, leaf, finish
from std.testing import assert_equal

def test_vectors() raises:
    for _ in range(3):
        hit("cached:1")
        assert_equal(branch("cached:2", True), True)
        assert_equal(branch("cached:2", False), False)
        _emit(String("COVLINE:diagnostic:1\n"))
        var values = List[Int]()
        _ = begin(values, 2)
        _ = leaf(True, values, "cached:3.0", 0)
        _ = leaf(False, values, "cached:3.1", 1)
        _ = finish(False, values, "cached:3")
    print("done")

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
IDENTITY = r'''from std.sys import argv
from std.pathlib import cwd

def main() raises:
    for item in argv():
        print(String(item))
    print(cwd())
'''


def require(condition, message):
    """Keep evidence checks active under optimized Python too."""
    if not condition:
        raise RuntimeError(message)


def invoke(mojo, work, suite, source, profile, arguments, environment):
    command = [sys.executable, str(ROOT/'tools/coverage_hit_aot.py'),
               '--profile', profile, '--root', str(work), '--suite', str(suite),
               '--cache', str(work/'native objects'), '--', mojo, 'run',
               '--Werror', '--num-threads', '1', '-I', str(ROOT), source,
               *arguments]
    result = subprocess.run(command, cwd=work, env=environment,
                            text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f'{profile}: {result.stdout}\n{result.stderr}')
    return result


def validate_capture(result, cache_phase):
    require(not result_errors(result.stdout), result.stdout)
    require(not slow_tests(result.stdout, 5), result.stdout)
    require('2 tests run: 2 passed , 0 failed , 0 skipped' in result.stdout,
            'native test inventory or status changed')
    require(result.stderr.count('COVLINE:diagnostic:1\n') == 3,
            'ordinary diagnostic multiplicity changed')
    require(result.stderr.count('COVEVAL2:runtime:decision:') == 1,
            'runtime constructor vector missing or duplicated')
    require(result.stderr.count('COVEVAL2:cached:3:') == 3,
            'complete repeated vector missing or duplicated')
    require(result.stderr.count('COVEVAL2:compile:decision:') == (cache_phase == 'cold'),
            'compile-time vector/cache-scope mismatch')
    expected = ['COVEVAL2:runtime:decision:F:TF;'] + ['COVEVAL2:cached:3:F:TF;'] * 3
    if cache_phase == 'cold':
        expected.insert(0, 'COVEVAL2:compile:decision:F:TF;')
    require([line for line in result.stderr.splitlines() if line.startswith('COVEVAL2:')] == expected,
            'independent complete-vector content or order changed')


def validate_streams(streams, profiles, identities, sources):
    for cache_phase in ('cold', 'warm'):
        raw = streams['raw', cache_phase]
        vectors = [x for x in raw.splitlines() if x.startswith('COVEVAL2:')]
        for profile in profiles:
            actual = streams[profile, cache_phase]
            require([x for x in actual.splitlines() if x.startswith('COVEVAL2:')] == vectors,
                    'complete vector sequence changed')
            require(set(actual.splitlines()) == set(raw.splitlines()),
                    'hit/evaluation evidence changed')
            if profile != 'aot-hits':
                require(actual == raw, 'uncached record multiplicity changed')
    for source in sources:
        require(all(identities[p, source] == identities['raw', source] for p in profiles),
                'source argv0, arguments or working directory changed')


def check(mojo):
    profiles = ['raw', 'aot']
    if platform.system() == 'Linux':
        profiles.append('aot-hits')
    with tempfile.TemporaryDirectory(prefix='threemojo coverage profile ') as folder:
        work = Path(folder)
        suite = work/'probe.mojo'
        suite.write_text(PROBE)
        identity = work/'identity.mojo'
        identity.write_text(IDENTITY)
        streams = {}
        identity_outputs = {}
        for profile in profiles:
            environment = dict(os.environ)
            for variable in ('LD_PRELOAD', 'DYLD_INSERT_LIBRARIES',
                             'THREEMOJO_COVERAGE_PIPE_DEVICE',
                             'THREEMOJO_COVERAGE_PIPE_INODE'):
                environment.pop(variable, None)
            environment['MODULAR_CACHE_DIR'] = str(work/('compiler-'+profile))
            environment['XDG_CACHE_HOME'] = str(work/('xdg-'+profile))
            for cache_phase in ('cold', 'warm'):
                result = invoke(mojo, work, suite, str(suite), profile, [], environment)
                validate_capture(result, cache_phase)
                streams[profile, cache_phase] = result.stderr
            for source in (str(identity), identity.name):
                arguments = ['argument with spaces', '--literal', source]
                result = invoke(mojo, work, identity, source, profile, arguments, environment)
                require(not result.stderr, result.stderr)
                identity_outputs[profile, source] = result.stdout
        validate_streams(streams, profiles, identity_outputs,
                         (str(identity), identity.name))
        if platform.system() == 'Linux':
            subprocess.run([sys.executable, str(ROOT/'tools/coverage_hit_faults.py'),
                            '--compile-run'], check=True, timeout=60)
    print('PASS: cold/warm phase records, every complete vector, ordinary diagnostics, '
          'absolute/relative source argv0, spaced paths/arguments and compiled profiles')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--mojo', default=str(ROOT/'.venv/bin/mojo'))
    args = parser.parse_args()
    check(str(Path(args.mojo).resolve()))


if __name__ == '__main__':
    main()
