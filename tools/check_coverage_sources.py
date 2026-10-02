# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check inherited defaults and collision-safe probes with the native compiler.

The fixtures run with a strict five-second process limit. Manifest expectations
are independent of the scanner. Raw records check original source identities,
short-circuit order, exceptional abandonment, and per-invocation buffers.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

DEFAULTS = '''"""Inherited bodies retain documentation."""
trait Choice:
    """One abstract requirement and a default."""
    def seed(self) -> Bool:
        """Implement this requirement."""
        ...  # abstract

    def choose(self, other: Bool) -> Bool:
        """Evaluate with a private invocation buffer."""
        if self.seed() and other:
            return True
        return False

@fieldwise_init
struct Default(Choice):
    var value: Bool
    def seed(self) -> Bool:
        return self.value

def main():
    var yes = Default(True)
    var no = Default(False)
    print(yes.choose(True), yes.choose(False), no.choose(True))
'''

STRESS = '''from std.testing import assert_equal

trait Inherited:
    def leaf(self, value: Bool, fail: Bool, mut order: String) raises -> Bool:
        order += "l"
        if fail:
            raise Error("expected")
        return value

    def choose(self, first: Bool, second: Bool, fail: Bool, mut order: String) raises -> Bool:
        if self.leaf(first, False, order) and self.leaf(second, fail, order):
            return True
        return False

    def recursive(self, depth: Int, mut order: String) -> Bool:
        order += "r"
        if depth > 0 and self.recursive(depth - 1, order):
            return True
        return False

    def nested(self) -> Bool:
        var List = 7
        var Int = 8
        var _cov_eval_buffer = True
        def inner(_cov_hit: Bool, _cov_branch: Bool) capturing -> Bool:
            if _cov_hit and _cov_branch:
                return True
            return False
        if invoke[inner]() and List == 7 and Int == 8 and _cov_eval_buffer:
            return True
        return False

struct Consumer(Inherited):
    def __init__(out self):
        pass

def invoke[_cov_branch: def(Bool, Bool) capturing[_] -> Bool]() -> Bool:
    if _cov_branch(True, False):
        return True
    return _cov_branch(True, True)

def legacy_collision() -> Int:
    var _cov_hit = 1
    var _cov_hit_ = 2
    var _cov_branch = 3
    var _cov_branch_ = 4
    var _cov_loop_LOOP = 40
    var _cov_loop__LOOP = 50
    for index in range(2):  # COLLIDING_LOOP
        if index > 0:
            _cov_hit += 1
    for index in range(0):
        _cov_branch += index
    return _cov_hit + _cov_hit_ + _cov_branch + _cov_branch_ + _cov_loop_LOOP + _cov_loop__LOOP

def main() raises:
    var value = Consumer()
    var order = String("")
    assert_equal(value.choose(False, True, False, order), False)
    assert_equal(order, "l")
    order = ""
    assert_equal(value.choose(True, False, False, order), False)
    assert_equal(order, "ll")
    order = ""
    assert_equal(value.choose(True, True, False, order), True)
    assert_equal(order, "ll")
    order = ""
    try:
        _ = value.choose(True, True, True, order)
    except error:
        order += "e"
    assert_equal(order, "lle")
    order = ""
    assert_equal(value.choose(True, False, False, order), False)
    assert_equal(order, "ll")
    order = ""
    assert_equal(value.recursive(3, order), False)
    assert_equal(order, "rrrr")
    assert_equal(value.nested(), True)
    assert_equal(legacy_collision(), 101)
    print("RESULT inherited defaults, exceptions, recursion, callbacks, collisions")
'''
LOOP = next(n for n, line in enumerate(STRESS.splitlines(), 1) if '# COLLIDING_LOOP' in line)
STRESS = STRESS.replace('LOOP', str(LOOP))


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def manifest(module, lines, decisions):
    rows = [f'L {module} {line}' for line in lines]
    for line, width in decisions:
        rows.append(f'B {module} {line}')
        for slot in range(width):
            rows.extend((f'C {module} {line} {slot}', f'M {module} {line} {slot}'))
    return '\n'.join(rows) + '\n'


def default_records():
    rows = ['COVLINE:defaults:21', 'COVLINE:defaults:22', 'COVLINE:defaults:23']
    for first, second, answer, body in [('T', 'T', 'T', 11), ('T', 'F', 'F', 12), ('F', '-', 'F', 12)]:
        rows.extend(('COVLINE:defaults:10', 'COVLINE:defaults:18', f'COVLINE:defaults:10.0:{first}'))
        if second != '-':
            rows.append(f'COVLINE:defaults:10.1:{second}')
        rows.extend((f'COVLINE:defaults:10:{answer}', f'COVEVAL2:defaults:10:{answer}:{first}{second};', f'COVLINE:defaults:{body}'))
    return '\n'.join(rows) + '\n'


def check_stress(raw, text):
    def records(marker):
        line = next(n for n, row in enumerate(STRESS.splitlines(), 1) if marker in row)
        prefix = f'COVEVAL2:stress:{line}:'
        return [row[len(prefix):] for row in raw.splitlines() if row.startswith(prefix)]
    assert records('if self.leaf(') == ['F:F-;', 'F:TF;', 'T:TT;', 'F:TF;']
    assert records('if depth > 0') == ['F:F-;', 'F:TF;', 'F:TF;', 'F:TF;']
    assert records('if _cov_hit and') == ['F:TF;', 'T:TT;']
    assert records('if invoke[inner]') == ['T:TTTT;']
    assert f'var _cov_loop___{LOOP} = 0' in text
    assert 'hit as _cov_hit__, branch as _cov_branch__' in text
    assert 'buffer as _cov_eval__buffer' in text
    assert f'COVLINE:stress:{LOOP}:T\n' in raw
    empty = next(n for n, row in enumerate(STRESS.splitlines(), 1) if 'range(0)' in row)
    assert f'COVLINE:stress:{empty}:F\n' in raw
    # The throwing second operand never creates a leaf or complete vector.
    choose = next(n for n, row in enumerate(STRESS.splitlines(), 1) if 'if self.leaf(' in row)
    assert raw.count(f'COVLINE:stress:{choose}.0:T\n') == 4
    assert raw.count(f'COVLINE:stress:{choose}.1:T\n') == 1
    assert raw.count(f'COVLINE:stress:{choose}.1:F\n') == 2



def check_trait_module(work, native, rewritten, mojo, output):
    """Import a trait-only module without a later definition to add imports."""
    source, _, consumer = DEFAULTS.partition('@fieldwise_init')
    consumer = 'from trait_only import Choice\n\n@fieldwise_init' + consumer
    (native / 'trait_only.mojo').write_text(source)
    for folder in (native, rewritten):
        (folder / 'consumer.mojo').write_text(consumer)
    run([str(work / 'build'), str(rewritten), 'trait_only.mojo'], cwd=native)
    text = (rewritten / 'trait_only.mojo').read_text()
    assert text.splitlines()[0] == source.splitlines()[0]
    assert text.splitlines()[1].startswith('from coverage.runtime import ')
    current_manifest = (rewritten / 'manifest.txt').read_text()
    assert current_manifest == manifest('trait_only', [10, 11, 12], [(10, 2)])
    results = []
    for folder in (native, rewritten):
        binary = folder / 'consumer'
        run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'consumer.mojo'), '-o', str(binary)], cwd=folder)
        results.append(run([str(binary)], timeout=5))
    assert results[0].stdout == results[1].stdout == 'True False False\n'
    assert not results[0].stderr
    # Caller and seed-method statements live in the unchanged consumer.
    expected = ''.join(row.replace(':defaults:', ':trait_only:') + '\n'
                       for row in default_records().splitlines()
                       if row not in [f'COVLINE:defaults:{n}' for n in (18, 21, 22, 23)])
    assert results[1].stderr == expected, results[1].stderr
    if output:
        (output / 'trait-only-manifest.txt').write_text(current_manifest)
        (output / 'trait-only-raw.txt').write_text(results[1].stderr)
        (output / 'trait-only-native.mojo').write_text(source)
        (output / 'trait-only-rewritten.mojo').write_text(text)
        (output / 'trait-only-consumer.mojo').write_text(consumer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    with tempfile.TemporaryDirectory(prefix='threemojo-sources-') as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        for folder in (native, rewritten):
            folder.mkdir()
            shutil.copytree(ROOT / 'coverage', folder / 'coverage', ignore=shutil.ignore_patterns('build'))
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/build_cli.mojo'), '-o', str(work / 'build')])
        for module, source in [('defaults', DEFAULTS), ('stress', STRESS)]:
            (native / f'{module}.mojo').write_text(source)
            run([str(work / 'build'), str(rewritten), f'{module}.mojo'], cwd=native)
            current_manifest = (rewritten / 'manifest.txt').read_text()
            if module == 'defaults':
                assert current_manifest == manifest('defaults', [10, 11, 12, 18, 21, 22, 23], [(10, 2)]), current_manifest
            results = []
            for folder in (native, rewritten):
                binary = folder / module
                run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / f'{module}.mojo'), '-o', str(binary)], cwd=folder)
                results.append(run([str(binary)], timeout=5))
            assert results[0].stdout == results[1].stdout
            assert not results[0].stderr
            if module == 'defaults':
                assert results[0].stdout == 'True False False\n'
                assert results[1].stderr == default_records(), results[1].stderr
            else:
                check_stress(results[1].stderr, (rewritten / f'{module}.mojo').read_text())
            if args.output:
                args.output.mkdir(parents=True, exist_ok=True)
                (args.output / f'{module}-manifest.txt').write_text(current_manifest)
                (args.output / f'{module}-raw.txt').write_text(results[1].stderr)
                for folder in (native, rewritten):
                    shutil.copy(folder / f'{module}.mojo', args.output / f'{module}-{folder.name}.mojo')
                (args.output / f'{module}-stdout.txt').write_text(results[0].stdout)
        check_trait_module(work, native, rewritten, mojo, args.output)
        print('PASS: trait-only imported module and inherited default exact L/B/C/M identities and full raw stream; abstract declarations, '
              'recursion, exceptions, nested generic callbacks, type and probe aliases, and exact loop-line collisions')


if __name__ == '__main__':
    main()
