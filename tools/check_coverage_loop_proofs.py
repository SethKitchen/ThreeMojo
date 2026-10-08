# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Native protocol and mutation qualification for constant-loop reporting.

Runtime probes remain those of the original instrumenter. Each executable
keeps the five-second limit; this harness never treats compiler failure as a
passing runtime test. Use after the compiler-free normal and -O controls.
"""

import argparse
from collections import defaultdict
import contextlib
import gzip
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

import coverage_io
import coverage_loop_proofs as proofs


ROOT = Path(__file__).resolve().parent.parent
SOURCE = '''from std.testing import assert_equal
from std.sys import argv

def fixed(leave: Int) raises -> Int:
    var total = 0
    for index in range(3):
        if leave == 1:
            break
        if leave == 2:
            return total
        if leave == 3:
            raise Error("expected body")
        if index == 0:
            continue
        total += index
    else:
        total += 10
    return total

def empty() -> Int:
    for index in range(0):
        return index
    else:
        return 7

def mark(value: Int, mut order: String) -> Int:
    order += String(value)
    return value

def literal() raises -> Int:
    var total = 0
    var order = String("")
    for value in [mark(1, order), mark(2, order), mark(3, order)]:
        assert_equal(order, "123")
        total += value
    return total

def dynamic(n: Int) -> Int:
    var total = 0
    for index in range(n):
        total += index
    return total

def main() raises:
    var mode = Int(String(argv()[1]))
    assert_equal(fixed(0), 13)
    assert_equal(fixed(1), 0)
    assert_equal(fixed(2), 0)
    var caught = False
    try:
        _ = fixed(3)
    except error:
        caught = String(error) == "expected body"
    assert_equal(caught, True)
    assert_equal(empty(), 7)
    assert_equal(literal(), 6)
    assert_equal(dynamic(2), 1)
    if mode == 0:
        assert_equal(dynamic(0), 0)
    print("RESULT constant loops")
'''


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(command, *, success=True, timeout=None, cwd=None):
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, cwd=cwd,
                               start_new_session=True)
    try:
        output, error = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    result = subprocess.CompletedProcess(command, process.returncode, output, error)
    if success and result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def line_of(fragment):
    matches = [number for number, line in enumerate(SOURCE.splitlines(), 1)
               if fragment in line]
    require(len(matches) == 1, 'Fixture identity is not unique: ' + fragment)
    return matches[0]


def capture_result(result, stem, envelope, command):
    """Keep raw/reduced diagnostic bytes; these are not production captures."""
    require(result.returncode == 0, 'Cannot record a failed native capture')
    raw = Path(str(stem) + '.raw.txt')
    raw.parent.mkdir(parents=True, exist_ok=True)
    output = Path(str(stem) + '.out')
    reduced = Path(str(stem) + '.txt.gz')
    raw.write_text(result.stderr)
    output.write_text(result.stdout)
    with gzip.open(reduced, 'wb') as stream:
        reducer = coverage_io.Reducer(stream.write)
        for record in result.stderr.encode().splitlines(keepends=True):
            reducer.feed(record)
    return raw, reduced


def diagnostic_manifest(original, envelope, module, lines):
    """Project only the loop outcomes for native reporter unit controls.

    Never mutate the original manifest/origin or claim an aggregate gate.
    """
    rows = []
    seen = set()
    for row in proofs.masked_manifest(original, envelope).splitlines():
        fields = row.split()
        if fields and fields[0] == b'P':
            rows.append(row)
        elif (len(fields) >= 3 and fields[0] in {b'B', b'R'}
              and fields[1].decode() == module and int(fields[2]) in lines):
            rows.append(row)
            seen.add(int(fields[2]))
    require(seen == set(lines), 'Diagnostic loop identity is missing')
    return b'\n'.join(rows) + b'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    compiler = run([mojo, '--version']).stdout.strip()
    flags = '-Werror -I .'

    def generate(root, stage, names, *, success=True, remove_after_begin=None):
        # The checkpoint precedes the command that loads the producer source.
        # A previously compiled unbound generator cannot attest current tools.
        proofs.begin_generation(root, stage, compiler, flags, mojo=[mojo], sources=names)
        if remove_after_begin is not None:
            (root / remove_after_begin).unlink()
        return run([mojo, 'run', '-Werror', '-I', '.', 'coverage/build_cli.mojo',
                    str(stage), *names], cwd=root, success=success)

    if args.output is None:
        workspace = tempfile.TemporaryDirectory(prefix='threemojo-loop-proofs-')
    else:
        retained = args.output.resolve() / 'attempt-work'
        retained.mkdir(parents=True, exist_ok=False)
        workspace = contextlib.nullcontext(str(retained))
    with workspace as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        native.mkdir()
        rewritten.mkdir()
        for name in proofs.TOOL_INPUTS:
            target = native / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        shutil.copytree(ROOT / 'coverage', rewritten / 'coverage',
                        ignore=shutil.ignore_patterns('build'))
        # Copy any remaining coverage package source too, matching the normal
        # uninstrumented tool copy-through contract.
        shutil.copytree(ROOT / 'coverage', native / 'coverage', dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('build'))
        shutil.copytree(ROOT / 'tools', native / 'tools', dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__'))
        (native / 'fixture.mojo').write_text(SOURCE)
        reporter = work / 'report'
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/report_cli.mojo'), '-o', str(reporter)])
        generate(native, rewritten, ['fixture.mojo'])
        full_manifest = (rewritten / 'manifest.txt').read_bytes()
        identities = {name: line_of(fragment) for name, fragment in {
            'fixed': 'for index in range(3)', 'empty': 'for index in range(0)',
            'literal': 'for value in [mark(1, order)', 'dynamic': 'for index in range(n)',
        }.items()}
        # A branch-only fixture manifest isolates outcome completeness from
        # intentionally unreachable literal-empty body lines. The untouched
        # full native manifest is retained as separate evidence.
        selected = ''.join(f'B fixture {line}\n' for line in identities.values()).encode()
        for record in selected.splitlines():
            require(record in full_manifest.splitlines(), 'Missing original fixture decision')
        envelope = proofs.seal(native, rewritten, compiler, flags, mojo=[mojo])
        require(len(envelope['receipt']['proofs']) == 3, 'Expected exactly three constant loops')
        totals = envelope['receipt']['denominator']
        require(totals['potential_total'] - totals['required_total'] == 3, 'Reachable outcome removed')
        evidence = work / 'evidence'
        evidence.mkdir()
        derived = evidence / 'derived-manifest.txt'
        derived.write_bytes(diagnostic_manifest(full_manifest, envelope, 'fixture', identities.values()))
        binaries = []
        for folder in [native, rewritten]:
            binary = folder / 'fixture'
            run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'fixture.mojo'), '-o', str(binary)])
            binaries.append(binary)
        results = {}
        for mode in [0, 1]:
            plain = run([str(binaries[0]), str(mode)], timeout=5)
            instrumented = run([str(binaries[1]), str(mode)], timeout=5)
            require(plain.stdout == instrumented.stdout == 'RESULT constant loops\n', 'Native output changed')
            require(not plain.stderr, 'Native program unexpectedly emitted probe records')
            by_line = defaultdict(list)
            for record in instrumented.stderr.splitlines():
                fields = record.split(':')
                if len(fields) == 4 and fields[:2] == ['COVLINE', 'fixture']:
                    by_line[int(fields[2])].append(fields[3])
            expected = {'fixed': 'TTTTTTT', 'empty': 'F', 'literal': 'TTTT',
                        'dynamic': 'TTTF' if mode == 0 else 'TTT'}
            for name, outcomes in expected.items():
                require(by_line[identities[name]] == list(outcomes), f'Loop protocol changed: {name}: {by_line[identities[name]]}')
            raw, reduced = capture_result(instrumented, evidence / f'case-{mode}' / 'result', envelope, [str(binaries[1]), str(mode)])
            reported = run([str(reporter), str(derived), str(raw)], success=False, timeout=5)
            require((reported.returncode == 0) == (mode == 0), 'Missing dynamic-empty obligation was lost')
            if mode == 0:
                require('TOTAL' in reported.stdout and '5/5' in reported.stdout, 'Positive report is incomplete')
                require('DENOMINATOR potential 8, required 5, proven impossible 3' in reported.stdout, 'Denominator lineage missing')
            else:
                require('never evaluated False' in reported.stdout, 'Dynamic-empty failure not explained')
            (evidence / f'report-{mode}.out').write_text(reported.stdout + reported.stderr)
            replayed = run([
                sys.executable, str(ROOT / 'tools/coverage_io.py'), 'report',
                '--capture-dir', str(reduced.parent), '--', str(reporter), str(derived),
            ], success=False, timeout=5)
            require((replayed.returncode == 0) == (mode == 0), 'Diagnostic raw/reduced reporting changed the result: ' + replayed.stdout + replayed.stderr)
            results[f'mode-{mode}'] = {'status': reported.returncode, 'expected': 'complete' if mode == 0 else 'dynamic-empty-missing'}
        # Mutation control: corrupt the actual native emitted entry probe of
        # a proved nonempty loop. It must be rejected, never discarded as
        # an infeasible hit. Counter/closer emissions remain unchanged.
        source_path = rewritten / 'fixture.mojo'
        original_instrumented = source_path.read_text()
        needle = f'_cov_branch("fixture:{identities["fixed"]}", True)'
        require(needle in original_instrumented, 'Mutation target absent')
        source_path.write_text(original_instrumented.replace(needle, needle.replace('True', 'False')))
        try:
            proofs.seal(native, rewritten, compiler, flags, mojo=[mojo])
        except ValueError as error:
            require('generation origin' in str(error), 'Unexpected mutation rejection')
        else:
            raise RuntimeError('Modified stage was accepted against the original source')
        mutant = rewritten / 'mutant'
        run([mojo, 'build', '-Werror', '-I', str(rewritten), str(source_path), '-o', str(mutant)])
        mutant_result = run([str(mutant), '0'], timeout=5)
        raw, _ = capture_result(mutant_result, evidence / 'mutation-capture' / 'result', envelope, [str(mutant), '0'])
        failed = run([str(reporter), str(derived), str(raw)], success=False, timeout=5)
        require(failed.returncode != 0 and 'Constant-loop proof contradicted' in failed.stderr,
                'Contradictory native probe was accepted')
        (evidence / 'mutant-report.out').write_text(failed.stdout + failed.stderr)
        mutated_source = source_path.read_text()
        source_path.write_text(original_instrumented)
        proofs.verify(rewritten / 'loop-proofs.json', native, rewritten, compiler, flags, mojo=[mojo])
        results['entry-probe-mutation'] = 'rejected contradictory actual native probe'
        # An explicit imported binding supplies an empty iterable even though
        # the call is spelled range(3). It must keep the original two-outcome
        # obligation, with a real F observation and no fabricated T.
        factory = 'def custom_range(n: Int) -> List[Int]:\n    return List[Int]()\n'
        shadow_source = '''from std.testing import assert_equal
from shadow_factory import custom_range as range

def main() raises:
    var visits = 0
    for item in range(3):
        visits += item + 1
    assert_equal(visits, 0)
    print("RESULT shadowed range")
'''
        (native / 'shadow.mojo').write_text(shadow_source)
        shadow_build = work / 'shadow-stage'
        shadow_build.mkdir()
        shutil.copytree(ROOT / 'coverage', shadow_build / 'coverage', ignore=shutil.ignore_patterns('build'))
        for folder in [native, shadow_build]:
            (folder / 'shadow_factory.mojo').write_text(factory)
        generate(native, shadow_build, ['shadow.mojo'])
        shadow_line = next(number for number, row in enumerate(shadow_source.splitlines(), 1)
                           if 'for item in range(3)' in row)
        shadow_selected = f'B shadow {shadow_line}\n'.encode()
        shadow_original = (shadow_build / 'manifest.txt').read_bytes()
        require(shadow_selected.strip() in shadow_original.splitlines(),
                'Shadow fixture original loop missing')
        shadow_proof = proofs.seal(native, shadow_build, compiler, flags, mojo=[mojo])
        require(not shadow_proof['receipt']['proofs'], 'Shadowed range incorrectly proved builtin')
        shadow_manifest = evidence / 'shadow-manifest.txt'
        shadow_manifest.write_bytes(diagnostic_manifest(shadow_original, shadow_proof, 'shadow', [shadow_line]))
        shadow_results = []
        for folder in [native, shadow_build]:
            binary = folder / 'shadow'
            run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'shadow.mojo'), '-o', str(binary)])
            shadow_results.append(run([str(binary)], timeout=5))
        require(shadow_results[0].stdout == shadow_results[1].stdout == 'RESULT shadowed range\n',
                'Shadowed range native semantics changed')
        require(not shadow_results[0].stderr, 'Unexpected native shadow probe')
        shadow_records = [row for row in shadow_results[1].stderr.splitlines()
                          if row.startswith(f'COVLINE:shadow:{shadow_line}:')]
        require(shadow_records == [f'COVLINE:shadow:{shadow_line}:F'], 'Shadowed range must emit only F')
        shadow_raw, _ = capture_result(shadow_results[1], evidence / 'shadow-capture' / 'result',
                                       shadow_proof, [str(shadow_build / 'shadow')])
        shadow_report = run([str(reporter), str(shadow_manifest), str(shadow_raw)], success=False, timeout=5)
        require(shadow_report.returncode != 0 and 'branches 1/2' in shadow_report.stdout,
                'Shadowed loop lost a reachable/unknown obligation')
        (evidence / 'shadow-report.out').write_text(shadow_report.stdout + shadow_report.stderr)
        results['shadowed-range'] = 'native empty custom iterable; both obligations retained; T remains missing'
        (native / 'shadow.mojo').write_text(shadow_source.replace(
            'from shadow_factory import custom_range as range', '# same-line builtin alias drift'))
        try:
            proofs.seal(native, shadow_build, compiler, flags, mojo=[mojo])
        except ValueError as error:
            require('generation origin' in str(error), 'Unexpected alias-drift rejection')
        else:
            raise RuntimeError('Same-line source alias drift was accepted')
        (native / 'shadow.mojo').write_text(shadow_source)
        results['native-alias-drift'] = 'rejected original/staged mismatch'
        # Actual CR/LF/UTF-8 generation records must retain the exact native
        # input and rewritten bytes; the original manifest remains unchanged.
        physical = 'from std.testing import assert_equal\n\ndef main() raises:\n    var text = String("é\tλ")\n    var total = 0\n    for index in range(2):\n        total += index\n    assert_equal(total, 1)\n    assert_equal(text, "é\tλ")\n    print("RESULT physical")\n'
        for number, ending in enumerate(['\n', '\r\n', '\r']):
            name = f'physical_{number}.mojo'
            original = physical.replace('\n', ending).encode()
            (native / name).write_bytes(original)
            stage = work / f'physical-{number}'
            stage.mkdir()
            shutil.copytree(ROOT / 'coverage', stage / 'coverage', ignore=shutil.ignore_patterns('build'))
            generate(native, stage, [name])
            bound = proofs.seal(native, stage, compiler, flags, mojo=[mojo])
            require(bound['receipt']['generation']['modules'][name]['source'] == proofs.sha256(original), 'Physical source bytes changed')
            observed = []
            for folder in [native, stage]:
                binary = folder / f'physical-{number}'
                run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / name), '-o', str(binary)])
                observed.append(run([str(binary)], timeout=5))
            require(observed[0].stdout == observed[1].stdout == 'RESULT physical\n', 'Physical-byte native parity failed')
            target = evidence / f'physical-{number}'
            target.mkdir()
            for record in [name, name + '.cov-origin', 'origins.ready', 'generation-inputs.json', 'manifest.txt', 'loop-proofs.json']:
                shutil.copyfile(stage / record, target / record)
        results['generation-byte-correspondence'] = 'native LF, CRLF, CR and UTF-8 pairs verified'
        # One complete original manifest goes through the maintained capture
        # wrapper and the official proof-aware reporting boundary end to end.
        production = 'def total(n: Int) -> Int:\n    var value = 0\n    for index in range(2):\n        value += index\n    for index in range(n):\n        value += index\n    return value\n'
        driver = 'from production import total\nfrom std.testing import assert_equal\n\ndef main() raises:\n    assert_equal(total(0), 1)\n    assert_equal(total(2), 2)\n    print("RESULT production capture")\n'
        (native / 'production.mojo').write_text(production)
        (native / 'tests').mkdir(exist_ok=True)
        suite_name = 'tests/test_production.mojo'
        (native / suite_name).write_text(driver)
        production_stage = work / 'production-stage'
        production_stage.mkdir()
        shutil.copytree(ROOT / 'coverage', production_stage / 'coverage', ignore=shutil.ignore_patterns('build'))
        (production_stage / 'tests').mkdir()
        (production_stage / suite_name).write_text(driver)
        generate(native, production_stage, ['production.mojo'])
        production_proof = proofs.seal(native, production_stage, compiler, flags,
                                       mojo=[mojo], suites=[suite_name])
        hits = production_stage / 'hits'
        hits.mkdir()
        command = [proofs._expand_path(word, native, production_stage) for word in
                   proofs.expected_capture_command(production_proof['receipt']['execution'], suite_name, 'raw')]
        capture = hits / 'test_production.txt.gz'
        output = hits / 'test_production.out'
        captured = run([sys.executable, str(ROOT / 'tools/coverage_io.py'), 'capture',
                        '--loop-proof', str(production_stage / 'loop-proofs.json'),
                        '--loop-proof-root', str(native), '--out', str(output), '--err', str(capture),
                        '--', *command], timeout=5)
        require(output.read_text() == 'RESULT production capture\n', 'Production capture output changed')
        reported = run([sys.executable, str(ROOT / 'tools/coverage_io.py'), 'report',
                        '--capture-dir', str(hits), '--loop-proof-root', str(native),
                        '--loop-proof-build', str(production_stage), '--compiler=' + compiler,
                        '--flags=' + flags, '--mojo', mojo, '--suites', suite_name, '--',
                        str(reporter), str(production_stage / 'manifest.txt')], timeout=5)
        require('100%' in reported.stdout and 'proven impossible 1' in reported.stdout,
                'Full original manifest failed the proof-aware production report')
        target = evidence / 'production'
        shutil.copytree(production_stage, target)
        (target / 'capture-process.out').write_text(captured.stdout + captured.stderr)
        (target / 'report-process.out').write_text(reported.stdout + reported.stderr)
        results['production-wrapper'] = 'actual raw capture and full original-manifest proof-aware report passed'
        (native / 'missing.mojo').write_text('def main():\n    pass\n')
        failed_generation = generate(native, shadow_build, ['shadow.mojo', 'missing.mojo'],
                                     success=False, remove_after_begin='missing.mojo')
        require(failed_generation.returncode != 0, 'Missing source regeneration unexpectedly succeeded')
        require((shadow_build / 'origins.ready').read_bytes() == b'', 'Failed generation left a usable prior index')
        results['interrupted-generation'] = 'old origin index invalidated before failing writes'
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            (args.output / 'full-original-manifest.txt').write_bytes(full_manifest)
            (args.output / 'original-loop-proofs.json').write_bytes(proofs.canonical(envelope) + b'\n')
            (args.output / 'shadow-loop-proofs.json').write_bytes(proofs.canonical(shadow_proof) + b'\n')
            (args.output / 'native-source.mojo').write_text(SOURCE)
            (args.output / 'original-instrumented.mojo').write_text(original_instrumented)
            (args.output / 'mutant-instrumented.mojo').write_text(mutated_source)
            for pattern in ['*.raw.txt', '*.out', '*.txt.gz', '*.proof.json', '*manifest.txt']:
                for path in evidence.rglob(pattern):
                    target = args.output / path.relative_to(evidence)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, target)
            (args.output / 'qualification.json').write_text(json.dumps(results, indent=2) + '\n')
            shutil.copytree(evidence, args.output / 'diagnostics', dirs_exist_ok=True)
        print('PASS: unchanged native loop streams; constant reachable outcomes; dynamic-empty negative; raw/reduced report parity; actual native entry-probe mutation rejected; shadowed range stays unknown')


if __name__ == '__main__':
    main()
