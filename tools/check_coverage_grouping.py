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
import textwrap

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
    ('scalar_bool(P0) and P1', ('and', 0, 1)),
    ('optional_value(P0)', 0),
    ('optional_custom(P0, order) or P1', ('or', 0, 1)),
    ('list_custom(P0, order) and P1', ('and', 0, 1)),
    ('not P0 or not (optional_value(P1) or P2)',
     ('or', ('not', 0), ('not', ('or', 1, 2)))),
    ('optional_value(P0) and (optional_value(P1) or P2)',
     ('and', 0, ('or', 1, 2))),
    ('text_value(P0) and Int(P1) or list_value(P2)',
     ('or', ('and', 0, 1), 2)),
    ('borrowed if P1 else borrowed',
     ('atom', ('choose', ('boolable', 0), 1, ('boolable', 0)))),
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
    if op == 'boolable':
        order.append('b')
        value = bool(mask & (1 << args[0]))
        if slot is not None:
            probes.append((slot[0], value))
            slot[0] += 1
        return value
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
    if isinstance(tree, int) or tree[0] in ('atom', 'boolable'):
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


@fieldwise_init
struct Observable(Movable, Boolable):
    var value: Bool
    var order: Pointer[String, MutUntrackedOrigin]

    def __bool__(self) -> Bool:
        self.order[] += "b"
        return self.value


def observable(value: Bool, mut order: String) -> Observable:
    return Observable(value, Pointer(to=order).unsafe_origin_cast[MutUntrackedOrigin]())


def scalar_bool(value: Bool) -> SIMD[DType.bool, 1]:
    return SIMD[DType.bool, 1](value)


def optional_value(value: Bool) -> Optional[List[Float64]]:
    if value:
        return List[Float64]([1.0])
    return None


def optional_custom(value: Bool, mut order: String) -> Optional[Observable]:
    if value:
        return observable(False, order)
    return None


def list_custom(value: Bool, mut order: String) -> List[Observable]:
    var items = List[Observable]()
    if value:
        items.append(observable(False, order))
    return items^


def text_value(value: Bool) -> String:
    return "x" if value else ""


def list_value(value: Bool) -> List[Int]:
    if value:
        return [1]
    return []


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
    var borrowed = observable((mask & 1) != 0, order)
    try:
'''
        decisions.append(len(text.splitlines()) + 1)
        text += f'''        if {expression}:
            print("RESULT", {number}, mask, fail, "T", order)
        else:
            print("RESULT", {number}, mask, fail, "F", order)
    except error:
        print("RESULT", {number}, mask, fail, "E", order, String(error))
    _ = borrowed.value
'''
    text += '\n\ndef test_semantics() raises:\n    var fail = Int(getenv("THREEMOJO_GROUPING_FAIL", "-1"))\n    for mask in range(64):\n'
    for number in range(len(CASES)):
        text += f'        case_{number}(mask, fail)\n'
    text += '\n\ndef main() raises:\n    TestSuite.discover_tests[__functions_in_module()]().run()\n'
    return text, decisions


def lifetime_source():
    """Observe move-only container destruction before later operands and bodies."""
    s = textwrap.dedent('''\
    @fieldwise_init
    struct Item(Movable):
        var id: Int
        var drops: Pointer[Int, MutUntrackedOrigin]
        def __deinit__(deinit self):
            self.drops[] = self.drops[] * 10 + self.id
            print("DROP", self.id, self.drops[])

    def optional(id: Int, full: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> Optional[Item]:
        print("MAKE", id)
        if full:
            return Optional[Item](Item(id, drops))
        return None

    def items(id: Int, full: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> List[Item]:
        print("MAKE", id)
        var result = List[Item]()
        if full:
            result.append(Item(id, drops))
        return result^

    def observe(id: Int, result: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> Bool:
        print("OBSERVE", id, drops[])
        return result
    ''')
    cases = []
    for kind in ('optional', 'items'):
        other = 'items' if kind == 'optional' else 'optional'
        for first in ('True', 'False'):
            for second in ('True', 'False'):
                left = f'{kind}(1, {first}, drops)'
                right = f'{kind}(2, {second}, drops)'
                mixed = f'{other}(2, {second}, drops)'
                observe = f'observe(3, {second}, drops)'
                for expression in (
                    f'{left} and {right}', f'{left} or {right}',
                    f'{left} and {observe}', f'{left} or {observe}',
                    f'({left} or {right}) and {observe}',
                    f'({left} and {right}) or {observe}',
                    f'not ({left} or {right})',
                    f'retained and {observe}', f'retained or {observe}',
                    f'(retained or {observe}) and {left}',
                    f'(retained and {observe}) or {left}',
                    f'{left} and {mixed}', f'{left} or {mixed}',
                ):
                    number = len(cases)
                    cases.append(expression)
                    s += f"""
def case_{number}():
    print("CASE", {number})
    var state = 0
    var drops = Pointer(to=state).unsafe_origin_cast[MutUntrackedOrigin]()
    var retained = {kind}(4, {first}, drops)
    if {expression}:
        print("BODY", {number}, state)
    else:
        print("ELSE", {number}, state)
    print("AFTER", {number}, Bool(retained), state)
"""
    s += '\ndef main():\n' + ''.join(
        f'    case_{number}()\n    print("END", {number})\n'
        for number in range(len(cases)))
    return s, cases


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def records(text, decision):
    return [line for line in text.splitlines()
            if line.startswith(f'COVLINE:fixture:{decision}:')
            or line.startswith(f'COVLINE:fixture:{decision}.')]


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
            expected_rows, expected_records, expected_vectors = [], defaultdict(list), defaultdict(list)
            for mask in range(64):
                for number, (_, tree) in enumerate(CASES):
                    order, probes = [], []
                    try:
                        outcome = 'T' if evaluate(tree, mask, fail, order, probes, [0]) else 'F'
                    except ValueError:
                        outcome = 'E'
                    suffix = ' fixture exception' if outcome == 'E' else ''
                    expected_rows.append(f'RESULT {number} {mask} {fail} {outcome} {"".join(order)}{suffix}')
                    line = decisions[number]
                    if leaves(tree) > 1:
                        for slot, value in probes:
                            expected_records[number].append(
                                f'COVLINE:fixture:{line}.{slot}:{"T" if value else "F"}')
                    if outcome != 'E':
                        expected_records[number].append(f'COVLINE:fixture:{line}:{outcome}')
                        if leaves(tree) > 1:
                            states = dict(probes)
                            vector = ''.join(
                                '-' if i not in states else ('T' if states[i] else 'F')
                                for i in range(leaves(tree)))
                            expected_vectors[number].append(f'COVEVAL2:fixture:{line}:{outcome}:{vector};')
            outputs = []
            for binary in binaries:
                with isolated_environment() as environment:
                    environment['THREEMOJO_GROUPING_FAIL'] = str(fail)
                    result = run([str(binary)], env=environment, timeout=10)
                assert not result_errors(result.stdout), result.stdout
                assert not slow_tests(result.stdout, 5), result.stdout
                program_output = result.stdout.partition('\nRunning ')[0].strip()
                assert program_output == '\n'.join(expected_rows), result.stdout
                rows = [line for line in result.stdout.splitlines() if line.startswith('RESULT ')]
                assert rows == expected_rows, (binary, fail, rows[:3], expected_rows[:3])
                outputs.append(result)
            raw = outputs[1].stderr
            for number, line in enumerate(decisions):
                assert records(raw, line) == expected_records[number], (number, fail)
                actual_vectors = [record for record in raw.splitlines()
                                  if record.startswith(f'COVEVAL2:fixture:{line}:')]
                assert actual_vectors == expected_vectors[number], (number, fail, actual_vectors[:3], expected_vectors[number][:3])
            reduced = []
            reducer = Reducer(reduced.append)
            for record in raw.encode().splitlines(keepends=True):
                reducer.feed(record)
            (work / f'raw-{fail}.txt').write_text(raw)
            (work / f'reduced-{fail}.txt').write_bytes(b''.join(reduced))
            if fail == -1:
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
        for fail in range(-1, 6):
            reports = [run([str(work / 'analyze'), str(work / f'{kind}-{fail}.txt')]).stdout
                       for kind in ('raw', 'reduced')]
            assert reports[0] == reports[1], f'raw/reduced Mojo traces differ at throwing leaf {fail}'
            (work / f'vectors-{fail}.txt').write_text(reports[0])
        # Two evaluations cover the decision, but leave two leaves incomplete.
        line = decisions[8]
        negative = ('COVLINE:fixture:{0}.0:F\nCOVLINE:fixture:{0}.1:F\n'
                    'COVLINE:fixture:{0}.2:F\nCOVLINE:fixture:{0}:F\n'
                    'COVEVAL2:fixture:{0}:F:FFF;\n'
                    'COVLINE:fixture:{0}.0:T\nCOVLINE:fixture:{0}:T\n'
                    'COVEVAL2:fixture:{0}:T:T--;\n').format(line)
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
        # A generic conversion must not silently alter custom __bool__ calls.
        # Native same-type `or` retests the selected value in the outer context.
        custom_source = '''@fieldwise_init
struct Custom(Movable, Boolable):
    var value: Bool
    var changing: Bool
    var calls: Pointer[Int, MutUntrackedOrigin]

    def __bool__(self) -> Bool:
        self.calls[] += 1
        return self.calls[] % 2 == 1 if self.changing else self.value

def main():
    var calls = 0
    var counter = Pointer(to=calls).unsafe_origin_cast[MutUntrackedOrigin]()
    var result = False
    if Custom(True, CHANGE, counter) or Custom(True, CHANGE, counter):
        result = True
    print("CUSTOM", result, calls)
'''
        for changing in (False, True):
            name = 'changing' if changing else 'stable'
            (native / 'custom.mojo').write_text(custom_source.replace('CHANGE', str(changing)))
            run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'custom.mojo'),
                 '-o', str(work / 'custom')])
            result = run([str(work / 'custom')], timeout=5)
            assert result.stdout.strip() == f'CUSTOM {not changing} 2', result.stdout
            (work / f'custom-{name}-native.txt').write_text(result.stdout)
            run([str(build), str(rewritten), 'custom.mojo'], cwd=native)
            custom_manifest = (rewritten / 'manifest.txt').read_text()
            assert sum(row.startswith('C custom ') for row in custom_manifest.splitlines()) == 2
            assert sum(row.startswith('M custom ') for row in custom_manifest.splitlines()) == 2
            (work / f'custom-{name}-manifest.txt').write_text(custom_manifest)
            result = subprocess.run([mojo, 'build', '-Werror', '-I', str(rewritten),
                                     str(rewritten / 'custom.mojo'), '-o', str(work / 'rejected')],
                                    text=True, capture_output=True)
            assert result.returncode != 0 and 'custom Boolable truth conversions are not yet supported' in result.stderr, result
            (work / f'custom-{name}-rejected.txt').write_text(result.stderr)

        lifetime, lifetime_cases = lifetime_source()
        (native / 'lifetime.mojo').write_text(lifetime)
        run([str(build), str(rewritten), 'lifetime.mojo'], cwd=native)
        lifetime_results = []
        for label, folder in (('native', native), ('instrumented', rewritten)):
            binary = work / f'lifetime-{label}'
            run([mojo, 'build', '-Werror', '-I', str(folder),
                 str(folder / 'lifetime.mojo'), '-o', str(binary)])
            result = run([str(binary)], timeout=5)
            lifetime_results.append(result.stdout)
            (work / f'lifetime-{label}.txt').write_text(result.stdout)
        assert lifetime_results[0] == lifetime_results[1], 'Container destruction order differs'
        (work / 'lifetime-cases.txt').write_text('\n'.join(lifetime_cases) + '\n')

        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for path in work.glob('*.txt'):
                shutil.copy(path, args.output / path.name)
            shutil.copy(native / 'lifetime.mojo', args.output / 'lifetime-native.mojo')
            shutil.copy(rewritten / 'lifetime.mojo', args.output / 'lifetime-instrumented.mojo')
            shutil.copy(native / 'fixture.mojo', args.output / 'native.mojo')
            shutil.copy(rewritten / 'fixture.mojo', args.output / 'instrumented.mojo')
            (args.output / 'manifest.txt').write_text('\n'.join(manifest) + '\n')
        print(f'PASS: {len(CASES)} native/instrumented cases, 64 truth assignments, normal and 6 throwing positions; '
              'exact order/count/outcomes, manifest C/M, raw/reduced Mojo vectors, and negative report; '
              f'{len(lifetime_cases)} container destructor-order cases')


if __name__ == '__main__':
    main()
