# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Verify complete coverage vectors under recursion, abandonment, and tasks.

Builds use the pinned compiler and -Werror. Each test keeps its five-second
limit. Concurrent captures are actual POSIX pipes. No GPU or network is used.
"""

import argparse
import os
import resource
from collections import Counter
from pathlib import Path
import shutil
import subprocess
import tempfile

from coverage_io import Reducer
from run_suite import result_errors, slow_tests
from test_environment import isolated_environment

ROOT = Path(__file__).resolve().parent.parent

SOURCE = '''from std.testing import TestSuite, assert_equal
from std.time import sleep
from render.tasks import TaskGroup


def mark(value: Bool, mut order: String, name: String) -> Bool:
    order += name
    return value


def recursive(depth: Int, mut order: String) -> Bool:
    if mark(depth > 0, order, "a") and recursive(depth - 1, order):
        return True
    return False


def throw_or_recurse(depth: Int, mut order: String) raises -> Bool:
    if depth == 0:
        raise Error("nested")
    try:
        return catches(depth - 1, order)
    except error:
        order += "c"
        return False


def catches(depth: Int, mut order: String) raises -> Bool:
    if mark(True, order, "b") and throw_or_recurse(depth, order):
        return True
    return False


def sometimes(index: Int, mut order: String) raises -> Bool:
    order += "x"
    if index == 0:
        raise Error("abandoned")
    return True


def abandoned(mut order: String):
    for index in range(3):
        try:
            if mark(index != 1, order, "p") and sometimes(index, order):
                order += "y"
        except error:
            order += "e"


def loop_and_elif(mut order: String):
    var index = 0
    while mark(index < 2, order, "w") and mark(True, order, "z"):
        index += 1
        if index == 1:
            continue
        order += "k"
    else:
        order += "q"
    for choice in range(3):
        if choice == 0:
            order += "0"
        elif mark(choice == 1, order, "l") and mark(True, order, "r"):
            order += "1"
        else:
            order += "2"


def invoke[callback: def(Bool) capturing[_] -> Bool]() -> Bool:
    return callback(True)


def nested(mut order: String) -> Bool:
    def inner(value: Bool) capturing -> Bool:
        if value and False:
            return True
        return False
    if mark(True, order, "n") and invoke[inner]():
        return True
    return False


def collision(mut order: String) -> Bool:
    var _cov_eval_state0 = True
    if mark(_cov_eval_state0, order, "g") and False:
        return True
    return False


def shadowed_types(mut order: String) -> Bool:
    var List = 7
    var Int = 8
    if mark(List == 7, order, "s") and Int == 8:
        return True
    return False


def two_space(mut order: String) -> Bool:
  if mark(True, order, "t") and False:
    return True
  return False


def paused(value: Bool) -> Bool:
    sleep(0.00001)
    return value


def concurrent_case(worker: Int, iteration: Int) -> Bool:
    if paused((worker + iteration) % 2 == 0) and paused(worker % 2 == 0):
        return True
    return False


async def task(worker: Int, totals: MutPointer[Int, MutAnyOrigin]):
    var total = 0
    for iteration in range(100):
        total += Int(concurrent_case(worker, iteration))
    totals[unsafe_offset=worker] = total


def test_sequential() raises:
    var order = String("")
    print("RESULT recursion", recursive(3, order), order)
    order = ""
    print("RESULT caught", catches(1, order), order)
    order = ""
    abandoned(order)
    print("RESULT abandoned", order)
    order = ""
    loop_and_elif(order)
    print("RESULT loop", order)
    order = ""
    print("RESULT nested", nested(order), order)
    order = ""
    print("RESULT collision", collision(order), order)
    order = ""
    print("RESULT types", shadowed_types(order), order)
    order = ""
    print("RESULT indentation", two_space(order), order)


def test_concurrent() raises:
    var totals = List[Int](length=8, fill=0)
    var group = TaskGroup()
    for worker in range(8):
        group.create_task(task(worker, totals.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()))
    group.wait()
    assert_equal(totals, [50, 0, 50, 0, 50, 0, 50, 0])
    print("RESULT concurrent", totals)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''

ANALYZER = '''from coverage.mcdc import parse_traces
from std.pathlib import Path
from std.sys import argv

def main() raises:
    var traces = parse_traces(Path(String(argv()[1])).read_text())
    for trace in traces:
        print(trace.id)
        for evaluation in trace.evaluations:
            print(evaluation.values, evaluation.outcome)
'''

BOUNDARY = '''from coverage.runtime import _emit, _emit_hit, hit, branch, begin, leaf, finish
from std.sys import argv
from render.tasks import TaskGroup

async def emit_many(record: String):
    for _ in range(100):
        _emit(record)

def main() raises:
    var size = Int(String(argv()[1]))
    if size == -1:
        hit("literal:1")
        _ = branch("literal:2", True)
        var values = List[Int]()
        _ = begin(values, 2)
        _ = leaf(True, values, "literal:4.0", 0)
        _ = leaf(False, values, "literal:4.1", 1)
        _ = finish(False, values, "literal:4")
        return
    if size == -511:
        _emit_hit("HIT_511", "\\n")
        return
    if size == -512:
        _emit_hit("HIT_512", "\\n")
        return
    if size == -513:
        _emit_hit("HIT_513", "\\n")
        return
    var concurrent = size == 0
    if concurrent:
        size = 512
    var record = String("COVEVAL2:é:1:T:")
    record += "T" * (size - record.byte_length() - 2)
    record += ";\\n"
    if concurrent:
        var group = TaskGroup()
        for _ in range(8):
            group.create_task(emit_many(record))
        group.wait()
    else:
        _emit(record)
'''

BOUNDARY = BOUNDARY.replace('HIT_511', 'é' * 250 + ':1').replace('HIT_512', 'é' * 250 + 'x:1').replace('HIT_513', 'é' * 250 + 'xx:1')


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def decision(source, marker):
    return next(index for index, line in enumerate(source.splitlines(), 1)
                if marker in line)


def vector_records(raw, line):
    prefix = f'COVEVAL2:fixture:{line}:'
    return [record[len(prefix):] for record in raw.splitlines() if record.startswith(prefix)]


def check_vectors(raw):
    cases = [
        ('if mark(depth > 0', ['F:F-;', 'F:TF;', 'F:TF;', 'F:TF;']),
        ('if mark(True, order, "b")', ['F:TF;']),
        ('if mark(index != 1', ['F:F-;', 'T:TT;']),
        ('while mark(index < 2', ['T:TT;', 'T:TT;', 'F:F-;']),
        ('elif mark(choice == 1', ['T:TT;', 'F:F-;']),
        ('if value and False:', ['F:TF;']),
        ('if mark(True, order, "n")', ['F:TF;']),
        ('if mark(_cov_eval_state0', ['F:TF;']),
        ('if mark(List == 7', ['T:TT;']),
        ('if mark(True, order, "t")', ['F:TF;']),
    ]
    for marker, expected in cases:
        actual = vector_records(raw, decision(SOURCE, marker))
        assert actual == expected, (marker, actual, expected)
    concurrent_line = decision(SOURCE, 'if paused(')
    concurrent = vector_records(raw, concurrent_line)
    active = peak = 0
    for record in raw.splitlines():
        if record.startswith(f'COVLINE:fixture:{concurrent_line}.0:'):
            active += 1
            peak = max(peak, active)
        elif record.startswith(f'COVEVAL2:fixture:{concurrent_line}:'):
            active -= 1
    assert active == 0 and peak >= 2, ('no actual overlap observed', active, peak)
    assert Counter(concurrent) == {'F:F-;': 400, 'F:TF;': 200, 'T:TT;': 200}, Counter(concurrent)
    # The first recorded operand from the abandoned pass remains a condition hit.
    abandoned = decision(SOURCE, 'if mark(index != 1')
    assert raw.count(f'COVLINE:fixture:{abandoned}.0:T\n') == 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    with tempfile.TemporaryDirectory(prefix='threemojo-protocol-') as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        for folder in (native, rewritten):
            folder.mkdir()
            shutil.copytree(ROOT / 'coverage', folder / 'coverage', ignore=shutil.ignore_patterns('build'))
            (folder / 'render').mkdir()
            for filename in ('__init__.mojo', 'tasks.mojo'):
                shutil.copy(ROOT / 'render' / filename, folder / 'render' / filename)
        (native / 'fixture.mojo').write_text(SOURCE)
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/build_cli.mojo'), '-o', str(work / 'build')])
        run([str(work / 'build'), str(rewritten), 'fixture.mojo'], cwd=native)
        text = (rewritten / 'fixture.mojo').read_text()
        assert 'var _cov_eval__state' in text
        binaries = []
        for folder in (native, rewritten):
            binary = folder / 'suite'
            run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'fixture.mojo'), '-o', str(binary)], cwd=folder)
            binaries.append(binary)
        expected = [
            'RESULT recursion False aaaa', 'RESULT caught False bbc',
            'RESULT abandoned pxeppxy', 'RESULT loop wzwzkwq0lr1l2',
            'RESULT nested False n', 'RESULT collision False g', 'RESULT types True s',
            'RESULT indentation False t', 'RESULT concurrent [50, 0, 50, 0, 50, 0, 50, 0]',
        ]
        for repeat in range(5):
            outputs = []
            for binary in binaries:
                with isolated_environment() as environment:
                    result = run([str(binary)], env=environment, timeout=10)
                assert not result_errors(result.stdout), result.stdout
                assert not slow_tests(result.stdout, 5), result.stdout
                program_output = result.stdout.partition('\nRunning ')[0].strip()
                assert program_output == '\n'.join(expected), result.stdout
                rows = [line for line in result.stdout.splitlines() if line.startswith('RESULT ')]
                assert rows == expected, rows
                outputs.append(result)
            raw = outputs[1].stderr
            assert all(record.startswith(('COVLINE:', 'COVEVAL2:')) for record in raw.splitlines()), 'torn probe record'
            assert all(len(record.encode()) + 1 <= 512 for record in raw.splitlines())
            check_vectors(raw)
            reduced = []
            reducer = Reducer(reduced.append)
            for record in raw.encode().splitlines(keepends=True):
                reducer.feed(record)
            (work / f'raw-{repeat}.txt').write_text(raw)
            (work / f'reduced-{repeat}.txt').write_bytes(b''.join(reduced))
            (work / f'native-{repeat}.txt').write_text(outputs[0].stdout)
            (work / f'instrumented-{repeat}.txt').write_text(outputs[1].stdout)
        (native / 'analyze.mojo').write_text(ANALYZER)
        run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'analyze.mojo'), '-o', str(work / 'analyze')])
        for repeat in range(5):
            reports = [run([str(work / 'analyze'), str(work / f'{kind}-{repeat}.txt')]).stdout
                       for kind in ('raw', 'reduced')]
            assert reports[0] == reports[1], f'raw/reduced vectors differ for concurrent capture {repeat}'
            (work / f'vectors-{repeat}.txt').write_text(reports[0])
        (native / 'boundary.mojo').write_text(BOUNDARY)
        run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'boundary.mojo'), '-o', str(work / 'boundary')])
        result = run([str(work / 'boundary'), '-1'])
        assert result.stderr == ('COVLINE:literal:1\nCOVLINE:literal:2:T\n'
                                 'COVLINE:literal:4.0:T\nCOVLINE:literal:4.1:F\n'
                                 'COVLINE:literal:4:F\nCOVEVAL2:literal:4:F:TF;\n'), result.stderr
        (work / 'literal-runtime-records.txt').write_text(result.stderr)
        for size in (511, 512):
            result = run([str(work / 'boundary'), str(size)])
            assert len(result.stderr.encode()) == size
            reduced = []
            Reducer(reduced.append).feed(result.stderr.encode())
            path = work / f'boundary-{size}.txt'
            path.write_text(result.stderr)
            run([str(work / 'analyze'), str(path)])
        for size in (511, 512):
            result = run([str(work / 'boundary'), str(-size)])
            assert len(result.stderr.encode()) == size
            assert result.stderr.startswith('COVLINE:')
            (work / f'hit-boundary-{size}.txt').write_text(result.stderr)
        result = subprocess.run([str(work / 'boundary'), '-513'], capture_output=True)
        assert result.returncode != 0 and b'COVLINE:' not in result.stderr, result
        result = run([str(work / 'boundary'), '0'])
        records = result.stderr.encode().splitlines(keepends=True)
        assert len(records) == 800 and all(len(record) == 512 for record in records)
        reduced = []
        reducer = Reducer(reduced.append)
        for record in records:
            reducer.feed(record)
        assert len(reduced) == 1
        (work / 'boundary-concurrent.txt').write_text(result.stderr)
        run([str(work / 'analyze'), str(work / 'boundary-concurrent.txt')])
        result = subprocess.run([str(work / 'boundary'), '513'], capture_output=True)
        assert result.returncode != 0 and b'COVEVAL2:' not in result.stderr, result
        (work / 'boundary-513-status.txt').write_text(str(result.returncode) + '\n')
        # A failed descriptor and a deterministic short file write both abort.
        failures = {}
        for mode in ('-1', '512'):
            result = subprocess.run([str(work / 'boundary'), mode], stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, preexec_fn=lambda: os.close(2))
            assert result.returncode != 0
            failures[f'closed-{mode}'] = result.returncode
            path = work / f'short-{mode}.txt'
            with path.open('wb') as output:
                result = subprocess.run([str(work / 'boundary'), mode], stdout=subprocess.PIPE,
                                        stderr=output, preexec_fn=lambda: resource.setrlimit(resource.RLIMIT_FSIZE, (10, 10)))
            assert result.returncode != 0 and len(path.read_bytes()) == 10
            failures[f'short-{mode}'] = result.returncode
        result = subprocess.run([str(work / 'analyze'), str(work / 'short-512.txt')], capture_output=True)
        assert result.returncode != 0, 'short write became an accepted vector'
        (work / 'write-failure-status.txt').write_text(str(failures) + '\n')

        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for path in work.glob('*.txt'):
                shutil.copy(path, args.output / path.name)
            shutil.copy(native / 'fixture.mojo', args.output / 'native.mojo')
            shutil.copy(rewritten / 'fixture.mojo', args.output / 'instrumented.mojo')
            shutil.copy(rewritten / 'manifest.txt', args.output / 'manifest.txt')
        print('PASS: recursive and caught-inner-exception vectors, same-frame abandonment, while/elif/continue/else, '
              'nested callbacks, new evaluation-name/type shadowing, 5 real-pipe 8-task captures, exact raw/reduced vectors, '
              'UTF-8 511/512-byte writes and 513-byte refusal')


if __name__ == '__main__':
    main()
