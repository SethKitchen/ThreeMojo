# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Run one directory's unittest tests in separate processes, several at once.

    python3 tools/parallel_unittest.py --jobs 4 tools/carla_lane_oracle

The #333 oracle tests copy whole repository roots and replay proofs; run one
after another they exceed a CI job's time limit, and one module alone takes
hours. A module with shared set-up (`setUpModule` or a `setUpClass`) runs as
one `python -m unittest discover -s DIR -p MODULE` process, exactly as plain
discovery loads it. Every other module runs one process per test, because
each test sets up its own fixtures. A failing unit prints its output in one
piece. The exit code is nonzero when a unit fails or no test is found.
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
ids, shared = [], False
def walk(item):
    global shared
    if isinstance(item, unittest.TestSuite):
        for child in item:
            walk(child)
        return
    if type(item).__name__ in ('_FailedTest', 'ModuleImportFailure'):
        shared = True
    cls = type(item)
    module = sys.modules.get(cls.__module__)
    if getattr(module, 'setUpModule', None) or getattr(module, 'tearDownModule', None):
        shared = True
    if cls.setUpClass.__func__ is not unittest.TestCase.setUpClass.__func__:
        shared = True
    if cls.tearDownClass.__func__ is not unittest.TestCase.tearDownClass.__func__:
        shared = True
    ids.append(item.id())
walk(suite)
print(json.dumps({'ids': ids, 'shared': shared}))
'''


def modules(directory, pattern='test_*.py'):
    """Return the test module file names in one directory, sorted."""
    return sorted(path.name for path in Path(directory).glob(pattern) if path.is_file())


def units(directory, name, python=sys.executable):
    """Return the commands that together run every test of one module."""
    listed = subprocess.run([python, '-c', _LIST, str(directory), name],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        found = json.loads(listed.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        found = {'ids': [], 'shared': True}
    if found['shared'] or listed.returncode != 0:
        return [(name, [python, '-m', 'unittest', 'discover', '-s', str(directory), '-p', name])]
    return [(test, [python, '-m', 'unittest', test]) for test in found['ids']]


def run_unit(directory, label, command):
    """Run one unit in the directory; return (label, return code, seconds, output)."""
    start = time.monotonic()
    result = subprocess.run(command, cwd=directory, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    return label, result.returncode, time.monotonic() - start, result.stdout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--jobs', type=int, default=4)
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
        # Whole-module units are the long ones; start them first.
        work.sort(key=lambda unit: unit[1][2] != 'discover')
        failed = []
        for label, code, seconds, output in pool.map(lambda u: run_unit(directory, *u), work):
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
