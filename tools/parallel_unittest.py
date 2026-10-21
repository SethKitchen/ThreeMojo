# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Run one directory's unittest tests in separate processes, several at once.

    python3 tools/parallel_unittest.py --jobs 4 tools/carla_lane_oracle

The #333 oracle tests copy whole repository roots and replay proofs; run one
after another they exceed a CI job's time limit, and one module alone takes
hours. A test without shared set-up runs alone in its own process. Tests of
one class with shared set-up (`setUpModule` or `setUpClass`) run a few at a
time, so each process repeats the cheap shared set-up for a short run of
tests. A module that cannot be listed runs as one `python -m unittest
discover -s DIR -p MODULE` process, exactly as plain discovery loads it.
`--shard I/N` keeps every N-th unit, so N runners together run each unit
once. A failing unit prints its output in one piece. The exit code is
nonzero when a unit fails or no test module is found.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import time

# Runs in a child process so that importing test modules leaves this one clean.
_LIST = r'''
import json, sys, unittest
directory, name = sys.argv[1], sys.argv[2]
suite = unittest.TestLoader().discover(directory, pattern=name, top_level_dir=directory)
tests, broken = [], False
def overridden(cls, name):
    return getattr(cls, name).__func__ is not getattr(unittest.TestCase, name).__func__
def walk(item):
    global broken
    if isinstance(item, unittest.TestSuite):
        for child in item:
            walk(child)
        return
    if type(item).__name__ in ('_FailedTest', 'ModuleImportFailure'):
        broken = True
    cls = type(item)
    module = sys.modules.get(cls.__module__)
    shared = bool(getattr(module, 'setUpModule', None) or getattr(module, 'tearDownModule', None)
                  or overridden(cls, 'setUpClass') or overridden(cls, 'tearDownClass'))
    tests.append([item.id(), shared])
walk(suite)
print(json.dumps({'tests': tests, 'broken': broken}))
'''


def modules(directory, pattern='test_*.py'):
    """Return the test module file names in one directory, sorted."""
    return sorted(path.name for path in Path(directory).glob(pattern) if path.is_file())


# Tests that share set-up run this many to a process; the set-up repeats.
CHUNK = 4

# Full-gate positive verification has fixed subprocess deadlines; retained
# cold-route identity proofs also have high peak memory use. Run these units
# without competing test processes. Keep groups, retention and limits unchanged.
_EXCLUSIVE_TEST = (
    'test_coverage_invariant_contracts.CoverageInvariantContracts.'
    'test_historical_direct_and_qualified_package_verification'
)

_EXCLUSIVE_TESTS = (
    _EXCLUSIVE_TEST,
    'test_coverage_invariant_contracts.CoverageInvariantContracts.'
    'test_direct_and_qualified_package_verification',
    'test_full_audit_cleanup_contracts.FullAuditCleanupContracts.'
    'test_consumer_first_import_orders_normal_and_optimized',
    'test_invariant_operation_inputs.OperationReachedBindingControls.'
    'test_current_cold_routes_preserve_consumed_value_bindings',
)


def _exclusive(command):
    """Select deadline/memory-sensitive proofs and whole-module fallbacks."""
    return any(test in command[3:]
               or (command[3:4] == ['discover']
                   and command[-2:] == ['-p', test.split('.')[0] + '.py'])
               for test in _EXCLUSIVE_TESTS)


def _run_scheduled(pool, directory, work):
    """Finish exclusive units before submitting the remaining parallel work."""
    parallel = []
    for unit in work:
        if _exclusive(unit[1]):
            yield run_unit(directory, *unit)
        else:
            parallel.append(unit)
    yield from pool.map(lambda u: run_unit(directory, *u), parallel)


def units(directory, name, python=sys.executable):
    """Return the commands that together run every test of one module."""
    listed = subprocess.run([python, '-c', _LIST, str(directory), name],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        found = json.loads(listed.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        found = {'tests': [], 'broken': True}
    if found['broken'] or listed.returncode != 0 or not found['tests']:
        return [(name, [python, '-m', 'unittest', 'discover', '-s', str(directory), '-p', name])]
    result, group = [], []
    def flush():
        if group:
            label = group[0] + ('' if len(group) == 1 else f' (+{len(group) - 1})')
            result.append((label, [python, '-m', 'unittest', *group]))
            group.clear()
    for test, shared in found['tests']:
        if group and (not shared or len(group) == CHUNK
                      or test.rsplit('.', 1)[0] != group[0].rsplit('.', 1)[0]):
            flush()
        group.append(test)
        if not shared:
            flush()
    flush()
    return result


def shard(text):
    """Parse canonical I/N with 1 <= I <= N."""
    try:
        index, count = (int(part) for part in text.split('/'))
    except ValueError:
        raise argparse.ArgumentTypeError('--shard must be I/N') from None
    if text != f'{index}/{count}':
        raise argparse.ArgumentTypeError('--shard must be canonical I/N')
    if not 1 <= index <= count:
        raise argparse.ArgumentTypeError('--shard must be I/N with 1 <= I <= N')
    return index, count


def run_unit(directory, label, command):
    """Run one unit in the directory; return (label, return code, seconds, output)."""
    start = time.monotonic()
    result = subprocess.run(command, cwd=directory, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    return label, result.returncode, time.monotonic() - start, result.stdout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--shard', type=shard, default=(1, 1))
    parser.add_argument('directory')
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error('--jobs must be at least 1')
    directory = Path(args.directory).resolve()
    names = modules(directory)
    if not names:
        print(f'no test modules in {args.directory}', file=sys.stderr)
        return 1
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        work = [unit for listed in pool.map(lambda n: units(directory, n), names) for unit in listed]
        index, count = args.shard
        work = work[index - 1::count]
        # Whole-module units are the long ones; start them first.
        work.sort(key=lambda unit: unit[1][2] != 'discover')
        failed = []
        for label, code, seconds, output in _run_scheduled(pool, directory, work):
            if code != 0:
                failed.append(label)
                print(f'== {label} ({seconds:.0f} s, exit {code})', flush=True)
                print(output, end='' if output.endswith('\n') else '\n', flush=True)
    print(f'{len(work) - len(failed)} of {len(work)} units passed '
          f'({len(names)} modules)', flush=True)
    if failed:
        print('failed: ' + ', '.join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
