# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compile native and instrumented Boolean fixtures and compare exact behavior.

This is a separate integration check because test-tools needs no compiler.
Every built suite retains the five-second per-test limit. Build time is not
part of that limit. No device or external service is used.
"""

import argparse
from collections import defaultdict
from pathlib import Path
import shutil
import subprocess
import tempfile

from coverage_io import Reducer
from run_suite import result_errors, slow_tests
from test_environment import isolated_environment

ROOT = Path(__file__).resolve().parent.parent

# A small independent Boolean tree supplies expected short-circuit order.
# An atomic subtree is deliberately opaque to the instrumenter.
CASES = [
    ('(((P0 or P1) and P2))', ('and', ('or', 0, 1), 2)),
    ('not (P0 and (P1 or not P2))', ('not', ('and', 0, ('or', 1, ('not', 2))))),
    ('(P0 or P1 and P2) and not not P3',
     ('and', ('or', 0, ('and', 1, 2)), ('not', ('not', 3)))),
    ('(\n            (P0 and P1)  # first group\n'
     '            or (not P2 and P3)\n        )',
     ('or', ('and', 0, 1), ('and', ('not', 2), 3))),
    ('(identity(P0 or P1, "and or") and values[Int(P2)] '
     'or (P3 and P4) == P5)',
     ('or', ('and', ('atom', ('or', 0, 1)), ('atom', 2)),
      ('atom', ('eq', ('and', 3, 4), 5)))),
    ('not(P0)or((P1)and(P2))', ('or', ('not', 0), ('and', 1, 2))),
    ('((quoted(mask, order, fail) == "\\\" and #:( or [") or P1) and P2',
     ('and', ('or', ('atom', 0), 1), 2)),
    ('(((not (P0))))', ('not', 0)),
    ('(P0 or P1 or P2)', ('or', ('or', 0, 1), 2)),
    ('P0 if P1 else P2 and P3', ('atom', ('choose', 0, 1, ('and', 2, 3)))),
    ('((P0 and P1) if P2 else (P3 or P4)) and P5',
     ('and', ('atom', ('choose', ('and', 0, 1), 2, ('or', 3, 4))), 5)),
    ('(not P0 if P1 else P2) or P3',
     ('or', ('atom', ('choose', ('not', 0), 1, 2)), 3)),
    ('(P1 or triple(mask, order, fail) == """hello" and word""")',
     ('or', 1, ('atom', 0))),
    ('(P1 or triple_lines(mask, order, fail) == """hello"\n# ) and or\nworld""")',
     ('or', 1, ('atom', 0))),
    ('P0 and (1 not in member_values(mask, order, fail))',
     ('and', 0, ('atom', ('not', 1)))),
]


def evaluate(tree, mask, fail, order, probes, slot):
    """Evaluate the independent reference tree with observable leaf calls."""
    if isinstance(tree, int):
        order.append(str(tree))
        if tree == fail:
            raise ValueError('fixture exception')
        value = bool(mask & (1 << tree))
        if slot is not None:
            probes.append((slot[0], value))
            slot[0] += 1
        return value
    op, *args = tree
    if op == 'choose':
        choose = evaluate(args[1], mask, fail, order, [], None)
        return evaluate(args[0] if choose else args[2], mask, fail, order, [], None)
    if op == 'atom':
        value = evaluate(args[0], mask, fail, order, [], None)
        probes.append((slot[0], value))
        slot[0] += 1
        return value
    if op == 'not':
        return not evaluate(args[0], mask, fail, order, probes, slot)
    left = evaluate(args[0], mask, fail, order, probes, slot)
    if op == 'and' and not left or op == 'or' and left:
        if slot is not None:
            slot[0] += leaves(args[1])
        return left
    right = evaluate(args[1], mask, fail, order, probes, slot)
    return left == right if op == 'eq' else right


def leaves(tree):
    if isinstance(tree, int) or tree[0] == 'atom':
        return 1
    return sum(leaves(child) for child in tree[1:])


def fixture_source():
    text = '''from std.os import getenv
from std.testing import TestSuite


def mark(mask: Int, index: Int, mut order: String, fail: Int) raises -> Bool:
    order += String(index)
    if index == fail:
        raise Error("fixture exception")
    return (mask & (1 << index)) != 0


def identity(value: Bool, text: String) -> Bool:
    _ = text
    return value


def member_values(mask: Int, mut order: String, fail: Int) raises -> List[Int]:
    return [Int(mark(mask, 1, order, fail)), 2]


def triple(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return 'hello" and word'
    return "different"


def triple_lines(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return """hello"
# ) and or
world"""
    return "different"


def quoted(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return '" and #:( or ['
    return "different"
'''
    decisions = []
    for number, (expression, tree) in enumerate(CASES):
        for index in range(6):
            expression = expression.replace(f'P{index}', f'mark(mask, {index}, order, fail)')
        text += f'''

def case_{number}(mask: Int, fail: Int) raises:
    var order = String("")
    var values: List[Bool] = [False, True]
    _ = values
    try:
'''
        decisions.append(len(text.splitlines()) + 1)
        text += f'''        if {expression}:
            print("RESULT", {number}, mask, fail, "T", order)
        else:
            print("RESULT", {number}, mask, fail, "F", order)
    except error:
        print("RESULT", {number}, mask, fail, "E", order, String(error))
'''
    text += '\n\ndef test_semantics() raises:\n    var fail = Int(getenv("THREEMOJO_GROUPING_FAIL", "-1"))\n    for mask in range(64):\n'
    for number in range(len(CASES)):
        text += f'        case_{number}(mask, fail)\n'
    text += '\n\ndef main() raises:\n    TestSuite.discover_tests[__functions_in_module()]().run()\n'
    return text, decisions


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def records(text, decision):
    return [line for line in text.splitlines()
            if line.startswith(f'COVBRANCH:fixture:{decision}:')
            or line.startswith(f'COVBRANCH:fixture:{decision}.')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='threemojo-grouping-') as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        for folder in (native, rewritten):
            folder.mkdir()
            shutil.copytree(ROOT / 'coverage', folder / 'coverage',
                            ignore=shutil.ignore_patterns('build'))
        source, decisions = fixture_source()
        (native / 'fixture.mojo').write_text(source)
        mojo = str(Path(args.mojo).resolve())
        build = work / 'build_cli'
        run([mojo, 'build', '-Werror', '-I', str(ROOT),
             str(ROOT / 'coverage/build_cli.mojo'), '-o', str(build)])
        run([str(build), str(rewritten), 'fixture.mojo'], cwd=native)
        manifest = (rewritten / 'manifest.txt').read_text().splitlines()
        for number, (_, tree) in enumerate(CASES):
            count = leaves(tree)
            expected = count if count > 1 else 0
            for kind in ('C', 'M'):
                actual = [line for line in manifest
                          if line.startswith(f'{kind} fixture {decisions[number]} ')]
                assert actual == [f'{kind} fixture {decisions[number]} {i}'
                                  for i in range(expected)], (number, actual)
        binaries = []
        for folder in (native, rewritten):
            binary = folder / 'suite'
            run([mojo, 'build', '-Werror', '-I', str(folder),
                 str(folder / 'fixture.mojo'), '-o', str(binary)], cwd=folder)
            binaries.append(binary)
        for fail in range(-1, 6):
            expected_rows, expected_records = [], defaultdict(list)
            for mask in range(64):
                for number, (_, tree) in enumerate(CASES):
                    order, probes = [], []
                    try:
                        outcome = 'T' if evaluate(tree, mask, fail, order, probes, [0]) else 'F'
                    except ValueError:
                        outcome = 'E'
                    suffix = ' fixture exception' if outcome == 'E' else ''
                    expected_rows.append(f'RESULT {number} {mask} {fail} {outcome} {"".join(order)}{suffix}')
                    # #385 covers abandoned evaluations. Only complete,
                    # non-recursive normal runs are reduced and compared.
                    if fail == -1:
                        line = decisions[number]
                        if leaves(tree) > 1:
                            for slot, value in probes:
                                expected_records[number].append(
                                    f'COVBRANCH:fixture:{line}.{slot}:{"T" if value else "F"}')
                        expected_records[number].append(f'COVBRANCH:fixture:{line}:{outcome}')
            outputs = []
            for binary in binaries:
                with isolated_environment() as environment:
                    environment['THREEMOJO_GROUPING_FAIL'] = str(fail)
                    result = run([str(binary)], env=environment, timeout=10)
                assert not result_errors(result.stdout), result.stdout
                assert not slow_tests(result.stdout, 5), result.stdout
                rows = [line for line in result.stdout.splitlines() if line.startswith('RESULT ')]
                assert rows == expected_rows, (binary, fail, rows[:3], expected_rows[:3])
                outputs.append(result)
            if fail == -1:
                raw = outputs[1].stderr
                for number, line in enumerate(decisions):
                    assert records(raw, line) == expected_records[number], number
                reduced = []
                reducer = Reducer(reduced.append)
                for line in raw.encode().splitlines(keepends=True):
                    reducer.feed(line)
                (work / 'raw.txt').write_text(raw)
                (work / 'reduced.txt').write_bytes(b''.join(reduced))
        # The real Mojo parser/report must agree on raw and reduced vectors.
        analyzer = '''from coverage.mcdc import parse_traces, is_mcdc_covered
from std.pathlib import Path
from std.sys import argv

def main() raises:
    var traces = parse_traces(Path(String(argv()[1])).read_text())
    for trace in traces:
        print(trace.id)
        for evaluation in trace.evaluations:
            print(evaluation.values, evaluation.outcome)
        for index in range(6):
            print(index, is_mcdc_covered(trace, index))
'''
        (native / 'analyze.mojo').write_text(analyzer)
        run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'analyze.mojo'),
             '-o', str(work / 'analyze')])
        reports = [run([str(work / 'analyze'), str(work / f'{kind}.txt')]).stdout
                   for kind in ('raw', 'reduced')]
        assert reports[0] == reports[1], 'raw/reduced Mojo traces differ'
        (work / 'vectors.txt').write_text(reports[0])
        # Two evaluations cover the decision, but leave two leaves incomplete.
        line = decisions[8]
        negative = ('COVBRANCH:fixture:{0}.0:F\nCOVBRANCH:fixture:{0}.1:F\n'
                    'COVBRANCH:fixture:{0}.2:F\nCOVBRANCH:fixture:{0}:F\n'
                    'COVBRANCH:fixture:{0}.0:T\nCOVBRANCH:fixture:{0}:T\n').format(line)
        (work / 'negative.txt').write_text(negative)
        (work / 'negative-manifest.txt').write_text('\n'.join(
            [f'B fixture {line}'] + [f'{kind} fixture {line} {i}'
                                   for i in range(3) for kind in ('C', 'M')]) + '\n')
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/report_cli.mojo'),
             '-o', str(work / 'report')])
        selected = [entry for entry in manifest
                    if entry.split()[0] in ('B', 'C', 'M')
                    and int(entry.split()[2]) in decisions]
        (work / 'decision-manifest.txt').write_text('\n'.join(selected) + '\n')
        for kind in ('raw', 'reduced'):
            result = run([str(work / 'report'), str(work / 'decision-manifest.txt'),
                          str(work / f'{kind}.txt')])
            (work / f'{kind}-report.txt').write_text(result.stdout)
        result = subprocess.run([str(work / 'report'), str(work / 'negative-manifest.txt'),
                                 str(work / 'negative.txt')], text=True, capture_output=True)
        assert result.returncode != 0
        (work / 'branch-manifest.txt').write_text(f'B fixture {line}\n')
        branch_report = run([str(work / 'report'), str(work / 'branch-manifest.txt'),
                             str(work / 'negative.txt')])
        assert '100%' in branch_report.stdout, branch_report.stdout
        (work / 'branch-report.txt').write_text(branch_report.stdout)
        assert 'condition 1:' in result.stdout and 'condition 2:' in result.stdout, result.stdout
        (work / 'negative-report.txt').write_text(result.stdout + result.stderr)
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for path in work.glob('*.txt'):
                shutil.copy(path, args.output / path.name)
            shutil.copy(native / 'fixture.mojo', args.output / 'native.mojo')
            shutil.copy(rewritten / 'fixture.mojo', args.output / 'instrumented.mojo')
            shutil.copy(rewritten / 'manifest.txt', args.output / 'manifest.txt')
        print(f'PASS: {len(CASES)} native/instrumented cases, 64 truth assignments, normal and 6 throwing positions; '
              'exact order/count/outcomes, manifest C/M, raw/reduced Mojo vectors, and negative report')


if __name__ == '__main__':
    main()
