# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compare native and rewritten loops at several valid indentation widths.

Fixtures carry their own source-line and decision identities. Exact loop
records check empty, exhausted, broken, continued, returned and raised paths.
Every executable retains the original five-second runtime limit.
"""

import argparse
from collections import defaultdict
from pathlib import Path
import shutil
import subprocess
import tempfile

from check_coverage_sources import manifest, run

ROOT = Path(__file__).resolve().parent.parent


def fixture(width, step, ending="\n", final_newline=True):
    rows, lines, decisions, labels = [], [], [], {}

    def add(depth, text, kind='', label=''):
        indent = 0 if not depth else width + (depth - 1) * step
        rows.append(' ' * indent + text)
        number = len(rows)
        if kind:
            lines.append(number)
        if kind == 'B':
            decisions.append((number, 0))
        if label:
            labels[label] = number

    add(0, 'from std.testing import assert_equal')
    add(0, 'def simple() raises:')
    add(1, 'var total = 0', 'L', 'simple_start')
    add(1, 'for index in range(2): # header', 'B', 'simple')
    add(0, '')
    add(0, '#\tA comment left of both suites must not establish indentation.')
    add(4, '# Nor can a more deeply indented comment.')
    add(2, 'total += index', 'L', 'simple_body')
    add(1, 'assert_equal(total, 1)', 'L', 'simple_end')
    add(0, '')
    add(0, 'def flow(n: Int, stop: Bool, leave: Bool) raises -> Int:')
    add(1, 'var total = 0', 'L')
    add(1, 'for outer in range( # start', 'B', 'outer')
    add(4, '# A header continuation is not a body.')
    add(3, 'n # value')
    add(1, '):')
    add(0, '')
    add(0, '# The body starts after comments.')
    add(2, 'var text = String("""literal\tvalue', 'L')
    add(0, 'for fake in range(0):')
    add(0, '# ) and else:')
    add(0, 'end""")')
    escaped_ending = ending.replace('\r', r'\r').replace('\n', r'\n')
    expected_literal = escaped_ending.join([r'literal\tvalue', 'for fake in range(0):', '# ) and else:', 'end'])
    add(2, f'assert_equal(text, "{expected_literal}")', 'L')
    add(2, 'for inner in range(2):', 'B', 'inner')
    add(3, 'if inner == 0:', 'B')
    add(4, 'continue', 'L')
    add(3, 'if stop:', 'B')
    add(4, 'break', 'L')
    add(3, 'total += outer + inner', 'L')
    add(3, 'if leave:', 'B')
    add(4, 'return total', 'L')
    add(2, 'else : # inner exhaustion')
    add(0, '# Preserve an intervening comment.')
    add(3, 'total += 10', 'L')
    add(1, 'else\t: # outer exhaustion')
    add(2, 'total += 100', 'L')
    add(1, 'return total', 'L')
    add(0, '')
    add(0, 'def exit_else(n: Int, fail: Bool) raises -> Int:')
    add(1, 'for _ in range(n):', 'B', 'exit_else')
    add(2, 'break', 'L')
    add(1, 'else:')
    add(2, 'if fail:', 'B')
    add(3, 'raise Error("expected else")', 'L')
    add(2, 'return 7', 'L')
    add(1, 'return 9', 'L')
    add(0, '')
    add(0, 'def throw_body() raises:')
    add(1, 'for _ in range(1):', 'B', 'throw_body')
    add(2, 'raise Error("expected body")', 'L')
    add(0, '')
    add(0, 'def literal_header() raises:')
    add(1, 'for index in range(', 'B', 'literal_header')
    add(3, 'String("""x')
    add(0, 'y""").byte_length() # a comment after the literal')
    add(3, f'- {len(ending) + 1}')
    add(1, '):')
    add(2, 'assert_equal(index, 0)', 'L')
    add(0, '')
    add(0, 'def main() raises:')
    add(1, 'simple()', 'L', 'main_start')
    add(1, 'assert_equal(flow(0, False, False), 100)', 'L', 'main_flow')
    add(1, 'assert_equal(flow(2, False, False), 123)', 'L')
    add(1, 'assert_equal(flow(2, True, False), 100)', 'L')
    add(1, 'assert_equal(flow(2, False, True), 1)', 'L')
    add(1, 'assert_equal(exit_else(0, False), 7)', 'L')
    add(1, 'assert_equal(exit_else(1, False), 9)', 'L')
    add(1, 'var caught = 0', 'L')
    add(1, 'try:', 'L')
    add(2, '_ = exit_else(0, True)', 'L')
    add(1, 'except error:')
    add(2, 'assert_equal(String(error), "expected else")', 'L')
    add(2, 'caught += 1', 'L')
    add(1, 'try:', 'L')
    add(2, 'throw_body()', 'L')
    add(1, 'except error:')
    add(2, 'assert_equal(String(error), "expected body")', 'L')
    add(2, 'caught += 1', 'L')
    add(1, 'assert_equal(caught, 2)', 'L')
    add(1, 'literal_header()', 'L')
    add(1, 'print("RESULT loops")', 'L')
    return ending.join(rows) + (ending if final_newline else ''), lines, decisions, labels


def check_records(raw, module, lines, decisions, labels):
    allowed = {f'COVLINE:{module}:{line}' for line in lines}
    for line, _ in decisions:
        allowed.update(f'COVLINE:{module}:{line}:{outcome}' for outcome in 'TF')
    records = raw.splitlines()
    assert set(records) <= allowed, set(records) - allowed
    by_line = defaultdict(list)
    for row in records:
        parts = row.split(':')
        if len(parts) == 4:
            by_line[int(parts[2])].append(parts[3])
    expected = {
        'simple': 'TTT',
        'outer': 'FTTTTTTT',
        'inner': 'TTTTTTTTTTTT',
        'exit_else': 'FTF',
        'throw_body': 'T',
        'literal_header': 'TT',
    }
    for label, outcomes in expected.items():
        assert by_line[labels[label]] == list(outcomes), (label, by_line[labels[label]], outcomes)
    # Pin the complete simple-loop stream, including line/branch interleaving.
    def line(label, suffix=''):
        return f'COVLINE:{module}:{labels[label]}{suffix}'
    assert records[:10] == [
        line('main_start'), line('simple_start'), line('simple'),
        line('simple', ':T'), line('simple_body'),
        line('simple', ':T'), line('simple_body'),
        line('simple', ':T'), line('simple_end'), line('main_flow'),
    ], records[:10]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--baseline-build', type=Path,
                        help='Optional frozen build_cli for negative controls.')
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='threemojo-loops-') as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        for folder in (native, rewritten):
            folder.mkdir()
            shutil.copytree(ROOT / 'coverage', folder / 'coverage', ignore=shutil.ignore_patterns('build'))
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/build_cli.mojo'), '-o', str(work / 'build')])
        cases = [(width, step, '\n', True) for width, step in [(1, 1), (2, 2), (3, 3), (4, 4), (8, 8), (2, 5)]]
        cases += [(2, 2, '\r\n', True), (2, 2, '\r', True), (2, 2, '\n', False)]
        for number, (width, step, ending, final_newline) in enumerate(cases):
            module = f'loops_{width}_{step}_{number}'
            source, lines, decisions, labels = fixture(width, step, ending, final_newline)
            (native / f'{module}.mojo').write_text(source)
            run([str(work / 'build'), str(rewritten), f'{module}.mojo'], cwd=native)
            current_manifest = (rewritten / 'manifest.txt').read_text()
            assert current_manifest == manifest(module, lines, decisions), current_manifest
            results = []
            for folder in (native, rewritten):
                binary = folder / module
                run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / f'{module}.mojo'), '-o', str(binary)], cwd=folder)
                results.append(run([str(binary)], timeout=5))
            assert results[0].stdout == results[1].stdout == 'RESULT loops\n'
            assert not results[0].stderr
            check_records(results[1].stderr, module, lines, decisions, labels)
            text = (rewritten / f'{module}.mojo').read_bytes().decode()
            assert ending.join(['"""literal\tvalue', 'for fake in range(0):', '# ) and else:', 'end"""']) in text
            assert '"""x' + ending + 'y"""' in text
            assert '#\tA comment left of both suites must not establish indentation.' in text
            if args.output:
                (args.output / f'{module}-manifest.txt').write_text(current_manifest)
                (args.output / f'{module}-raw.txt').write_text(results[1].stderr)
                (args.output / f'{module}-native.mojo').write_text(source)
                (args.output / f'{module}-rewritten.mojo').write_text(text)
                (args.output / f'{module}-stdout.txt').write_text(results[0].stdout)
        if args.baseline_build:
            # Isolate the original two-space failure from the independent else
            # adjacency failure, using original sources already valid natively.
            for name, source in [
                ('two_space', 'def main():\n  var total = 0\n  for index in range(2):\n    total += index\n  print(total)\n'),
                ('four_space_else', 'def main():\n    for index in range(0):\n        print(index)\n    else:\n        print("else")\n'),
            ]:
                (native / f'{name}.mojo').write_text(source)
                run([mojo, 'build', '-Werror', str(native / f'{name}.mojo'), '-o', str(native / name)])
                original = run([str(native / name)], timeout=5)
                run([str(args.baseline_build.resolve()), str(rewritten), f'{name}.mojo'], cwd=native)
                failed = subprocess.run([mojo, 'build', '-Werror', str(rewritten / f'{name}.mojo'), '-o', str(rewritten / name)], text=True, capture_output=True)
                assert failed.returncode != 0, name
                diagnostic = 'statement indentation must match' if name == 'two_space' else 'unexpected'
                assert diagnostic in failed.stderr, failed.stderr
                if args.output:
                    (args.output / f'baseline-{name}-native.mojo').write_text(source)
                    (args.output / f'baseline-{name}-rewritten.mojo').write_text((rewritten / f'{name}.mojo').read_text())
                    (args.output / f'baseline-{name}-diagnostic.txt').write_text(failed.stderr)
                    (args.output / f'baseline-{name}-stdout.txt').write_text(original.stdout)
        print('PASS: nine native/instrumented loop fixtures; LF/CRLF/CR and unterminated final lines; tabs in headers/literals/comments; widths 1, 2, 3, 4, 8 and mixed 2/5; exact source identities and loop outcomes; comments, multiline headers/literals, nested loops, break/continue/return, for-else and exceptions')


if __name__ == '__main__':
    main()
