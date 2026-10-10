# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Plan CI by directed source impact; run the existing Makefile with exact lists.

Execution follows changed inputs toward their consumers, never back through
an unchanged dependency to unrelated consumers. Coverage has its own inventory:
measure changed production modules and their production consumers; capture all
current suites that can reach them. Edited tests run without remeasuring every
unchanged import. Deleted tests and removed imports retain baseline obligations.
An assertion-only test deletion can reduce unchanged-library coverage without
a scoped gate detecting it; the explicit full audit owns that global guarantee.
Unknown inputs or history select a full audit. Invalid plans fail, never pass.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import affected

ROOT = Path(__file__).resolve().parents[1]
LIB_DIRS = set('math render units cameras core geometries helpers objects renderers materials lights loaders animation postprocessing controls window exporters environments generators extensions'.split())
GPU = {'render/gpu.mojo', 'render/gpu_vxgi.mojo', 'tests/test_gpu.mojo',
       'tests/test_gpu_layout.mojo', 'tests/test_gpu_volume_packing.mojo', 'bench/raster_bench.mojo'}
GPU_TESTS = {name for name in GPU if name.startswith('tests/')}
GLOBAL_TOOLS = {'tools/cache_key.py', 'tools/suite_key.py', 'tools/run_suite.py',
                'tools/shard.py', 'tools/native_test_support.py', 'tools/test_environment.py',
                'tools/fixture_runtime.py', 'tools/compiler_telemetry.py'}
ROUTING = {'tools/ci_scope.py', '.github/workflows/ci.yml'}
SAFE_PATH = re.compile(r'[A-Za-z0-9_./-]+\Z')
LISTS = ('formatted', 'cpu_entries', 'cpu_docs', 'cpu_tests', 'compile_fail',
         'covered', 'coverage_tests')
FLAGS = ('tools', 'native', 'cpu', 'coverage', 'gpu', 'docs', 'coverage_tools',
         'portability', 'export')
JOBS = {'lint': 'lint', 'cpu': 'cpu', 'cpu-macos': 'cpu',
        'lint-macos': 'lint', 'coverage-capture': 'coverage',
        'coverage': 'coverage', 'gpu-host': 'gpu'}


def library(path):
    return path.split('/')[0] in LIB_DIRS and path.endswith('.mojo')


def kind(path):
    """Explicit tooling exceptions; unknown inputs still require a full audit."""
    if path in GLOBAL_TOOLS or path == 'Makefile':
        return 'all'
    if path == 'bench/results-linux.json':
        return 'tools'
    if affected.is_documentation(path):
        return 'docs'
    if path in ROUTING or path.startswith('tools/test_') and path.endswith('.py'):
        return 'tools'
    if (path.startswith(('coverage/', 'tools/coverage_', 'tools/check_coverage_',
                         'tools/fixtures/coverage_', 'tools/carla_lane_oracle/'))):
        return 'coverage_tools'
    if path == 'tools/check_portability.py':
        return 'portability'
    if path in {'assets/carla/tools/carla_assets.py',
                'assets/carla/tools/test_carla_assets.py'}:
        return 'tools'
    if path.startswith('assets/carla/tools/export/'):
        return 'export'
    # These generators have exact compiler-free replay gates in test-tools.
    if path in {'tools/bench_examples.py', 'tools/compiler_metadata.py',
                'tools/humanoid_fidelity.py',
                'tools/generate_carla_lane_distance_controls.py',
                'tools/generate_carla_power_controls.py',
                'tools/generate_carla_directed_controls.py',
                'tools/generate_carla_index_controls.py'}:
        return 'tools'
    if path.startswith('assets/'):
        return 'native'
    if path.endswith('.mojo') and path.split('/')[0] in LIB_DIRS | {'tests', 'examples', 'bench', 'tools'}:
        return 'native'
    return 'all'


def graph(sources):
    known = set(sources)
    # Any entry point can compile a module, so keep every root it can use.
    lookup = affected.resolver(known, affected.entry_directories(sources))
    imports, users = {}, {}
    for path, source in sources.items():
        for name in affected.imported_names(source):
            for target in lookup(name):
                if target != path:
                    imports.setdefault(path, set()).add(target)
                    users.setdefault(target, set()).add(path)
    return imports, users


def source_tree():
    with_root = affected.ROOT
    try:
        affected.ROOT = str(ROOT)
        return {name: (ROOT / name).read_text(encoding='utf-8')
                for name in affected.mojo_files()}
    finally:
        affected.ROOT = with_root


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout


def changed_paths(base):
    """NUL-delimited paths; missing/divergent history is a full audit."""
    try:
        revision = git('merge-base', '--', base, 'HEAD').strip()
        # A normal PR base and a push's previous main are ancestors of the
        # checkout. Unknown/force-diverged history must not omit old inputs.
        resolved = git('rev-parse', '--verify', base + '^{commit}').strip()
        if revision != resolved:
            return None
        raw = git('diff', '--name-status', '--no-renames', '-z', revision, '--')
        fields = raw.split('\0')
        if fields[-1] or (len(fields) - 1) % 2:
            return None
        paths = {}
        for status, path in zip(fields[0:-1:2], fields[1:-1:2]):
            if status not in {'A', 'M', 'D', 'T'} or not path or path in paths:
                return None
            paths[path] = status == 'D'
        untracked = git('ls-files', '--others', '--exclude-standard', '-z')
        if untracked and not untracked.endswith('\0'):
            return None
        for path in filter(None, untracked.split('\0')):
            if path.endswith(('.mojo', '.py', '.c', '.h')) or path.startswith('assets/'):
                paths[path] = False
        return paths
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        return None


def previous_tests(base, changed, current):
    """Load old tests/helpers and reexports lazily, so removed edges survive."""
    tests = {name for name in changed if name.startswith('tests/') and name.endswith('.mojo')}
    if not tests:
        return {}
    revision = git('merge-base', base, 'HEAD').strip()
    known = set(filter(None, git('ls-tree', '-r', '--name-only', '-z', revision).split('\0')))
    old = {path: git('show', revision + ':' + path) for path in tests & known}
    removed = {path for path, source in old.items() if changed[path] or
               set(affected.imported_names(source)) - set(affected.imported_names(current.get(path, '')))}
    if not removed:
        return {}
    # Resolve against the actual historical filenames. Combining current
    # filenames with old imports lets a newly added sibling shadow steal an
    # old dependency. Batch blob reads avoid one Git process per source.
    entries = []
    for record in filter(None, git('ls-tree', '-r', '-z', revision).split('\0')):
        metadata, path = record.split('\t', 1)
        mode, object_type, identity = metadata.split()
        if path.endswith('.mojo'):
            if object_type != 'blob' or mode not in {'100644', '100755'}:
                raise ValueError('Unsupported baseline source entry')
            entries.append((path, identity))
    result = subprocess.run(['git', 'cat-file', '--batch'], cwd=ROOT, check=True,
                            input=''.join(identity + '\n' for _, identity in entries).encode(),
                            capture_output=True).stdout
    offset, old = 0, {}
    for path, identity in entries:
        end = result.index(b'\n', offset)
        found, object_type, size = result[offset:end].decode('ascii').split()
        if found != identity or object_type != 'blob':
            raise ValueError('Baseline source object mismatch')
        offset = end + 1
        size = int(size)
        raw = result[offset:offset + size]
        if len(raw) != size or result[offset + size:offset + size + 1] != b'\n':
            raise ValueError('Truncated baseline source object')
        old[path] = raw.decode('utf-8')
        offset += size + 1
    if offset != len(result):
        raise ValueError('Trailing baseline object data')
    return old


def inventories(sources):
    files = set(sources)
    helpers = {name for name in files if name.startswith('tests/_')}
    helpers |= {'tests/carla_fixed_s_fixture.mojo', 'tests/exact_predicates_oracle.mojo',
                'tools/anatomy_pairs.mojo'} & files
    libs = {name for name in files if library(name) and not name.endswith('/__init__.mojo')}
    tool_libs = {name for name in files if name.startswith('coverage/')}
    tool_libs -= {'coverage/build_cli.mojo', 'coverage/report_cli.mojo'}
    entries = {name for name in files if name.split('/')[0] in {'tests', 'examples', 'bench', 'tools'}
               and not name.startswith(('tests/compile_fail/', 'bench/mojo10/'))} - helpers
    entries |= {'coverage/build_cli.mojo', 'coverage/report_cli.mojo'} & files
    negative = {name for name in files if name.startswith('tests/compile_fail/')}
    tests = {name for name in files if re.fullmatch(r'tests/test_[^/]+\.mojo', name)}
    return {'formatted': libs | tool_libs | helpers | entries | negative,
            'cpu_entries': entries - GPU, 'cpu_docs': (libs | tool_libs | helpers) - GPU,
            'cpu_tests': tests - GPU_TESTS, 'compile_fail': negative,
            'covered': libs - GPU, 'coverage_tests': tests - GPU_TESTS}


def plan(changed, *, base=None, old=None):
    sources = source_tree()
    inventory = inventories(sources)
    full = changed is None or any(kind(name) == 'all' for name in changed)
    reason = 'full audit: unknown input/history or manual request' if full else 'directed input selection'
    types = {kind(name) for name in changed or {}}
    if full:
        selected = inventory
    else:
        imports, users = graph(sources)
        seeds = {name for name in changed if name in sources}
        assets = [name for name in changed if name.startswith('assets/') and kind(name) == 'native']
        for name, source in sources.items():
            if any(asset.startswith(quoted) for quoted in affected.QUOTED_ASSET.findall(source)
                   for asset in assets):
                seeds.add(name)
        # Deleted modules remain reverse-graph targets during resolution.
        if any(deleted and name.endswith('.mojo') for name, deleted in changed.items()):
            graph_sources = dict(sources)
            graph_sources.update({name: '' for name, deleted in changed.items()
                                  if deleted and name.endswith('.mojo')})
            imports, users = graph(graph_sources)
        execution = affected.reachable(seeds | {name for name in changed if name.endswith('.mojo')}, users)
        tests = {name for name in execution if name.startswith('tests/')}
        measured = {name for name in execution if library(name)}
        if old is None and any(name.startswith('tests/') and name.endswith('.mojo') for name in changed):
            try:
                old = previous_tests(base, changed, sources)
            except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError):
                return plan(None)
        if old:
            # Old graph keeps removed imports; current graph keeps additions.
            baseline = old
            old_imports, old_users = graph(baseline)
            removed = {name for name in old if name in changed and
                       (changed[name] or set(affected.imported_names(old[name])) -
                        set(affected.imported_names(sources.get(name, ''))))}
            old_tests = affected.reachable(removed, old_users)
            measured |= {name for name in affected.reachable(old_tests, old_imports) if library(name)}
        measured &= inventory['covered']
        captures = affected.reachable(measured, users) | tests
        selected = {name: values & execution for name, values in inventory.items()}
        selected['formatted'] = inventory['formatted'] & changed.keys()
        selected['covered'] = measured
        selected['coverage_tests'] = inventory['coverage_tests'] & captures
    values = {name: sorted(selected[name]) for name in LISTS}
    flags = {
        'tools': full or bool(types - {'docs'}),
        'native': full or bool(values['formatted'] or values['cpu_entries'] or values['cpu_docs'] or values['compile_fail']),
        'cpu': full or bool(values['cpu_tests']),
        'coverage': full or bool(values['covered']),
        'gpu': full or bool(execution & GPU),
        'docs': full or 'docs' in types,
        'coverage_tools': full or 'coverage_tools' in types or 'render/tasks.mojo' in (changed or {}),
        'portability': full or 'portability' in types or bool(execution & {'tests/portability_probe.mojo', 'tests/test_scratch.mojo'}),
        'export': full or 'export' in types,
    }
    flags['lint'] = any(flags[name] for name in ('tools', 'native', 'docs', 'coverage_tools', 'portability', 'export'))
    result = {'schema': 1, 'full': full, 'reason': reason, 'flags': flags, 'files': values}
    validate(result)
    return result


def validate(value):
    if (not isinstance(value, dict) or value.get('schema') != 1
            or type(value.get('full')) is not bool or not isinstance(value.get('reason'), str)
            or set(value.get('flags', {})) != set(FLAGS) | {'lint'}
            or set(value.get('files', {})) != set(LISTS)):
        raise ValueError('Invalid or missing CI plan')
    if any(type(flag) is not bool for flag in value['flags'].values()):
        raise ValueError('CI flags must be booleans')
    for paths in value['files'].values():
        if not isinstance(paths, list) or any(not isinstance(path, str) or not SAFE_PATH.fullmatch(path)
                or path.startswith('/') or '..' in path.split('/') or not path.endswith('.mojo') for path in paths):
            raise ValueError('Unsafe native Makefile path in CI plan')
        if len(paths) != len(set(paths)):
            raise ValueError('Duplicate CI path')
    for flag, name in [('cpu', 'cpu_tests'), ('coverage', 'covered')]:
        if value['flags'][flag] != bool(value['files'][name]) and not value['full']:
            raise ValueError('CI applicability disagrees with its inventory')
    return value


def selection_makefile(value, arguments):
    validate(value)
    files = value['files']
    coverage = any(arg == 'coverage' or arg.startswith('coverage-') for arg in arguments)
    mapping = {'FORMATTED': 'formatted', 'CPU_ENTRY_POINTS': 'cpu_entries',
               'CPU_DOC_SOURCES': 'cpu_docs', 'CPU_TESTS': 'coverage_tests' if coverage else 'cpu_tests',
               'COMPILE_FAIL_RUN': 'compile_fail', 'COVERED': 'covered'}
    return ''.join('override ' + name + ' := ' + ' '.join(files[key]) + '\n'
                   for name, key in mapping.items())


def make_command(value, arguments, selection_file):
    validate(value)
    # MAKEFILES is read before Makefile, and inherited by recursive make.
    # Lists stay in a file: large argv assignments overflow exported MAKEFLAGS.
    # Full audits use the unchanged native inventories, with no list overrides.
    scoped = any(arg in {'fmt-check', 'lint-cpu', 'compile-fail', 'test-cpu', 'coverage'}
                 or arg.startswith('coverage-') for arg in arguments)
    return ['make', '-B', *arguments, 'AFFECTED=',
            'MAKEFILES=' + (str(selection_file) if scoped and not value['full'] else '')]


def aggregate(value, needs):
    validate(value)
    if set(needs) != set(JOBS) | {'scope'} or needs['scope'].get('result') != 'success':
        raise ValueError('CI selection failed or a required job result is missing')
    for job, flag in JOBS.items():
        wanted = 'success' if value['flags'][flag] else 'skipped'
        if needs[job].get('result') != wanted:
            raise ValueError(f'{job}: expected {wanted}, got {needs[job].get("result")}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('action', choices=['plan', 'run', 'aggregate'])
    parser.add_argument('--base')
    parser.add_argument('--full', action='store_true')
    args, command = parser.parse_known_args(argv)
    if args.action == 'plan':
        changes = None if args.full or not args.base else changed_paths(args.base)
        value = plan(changes, base=args.base)
        encoded = json.dumps(value, separators=(',', ':')).encode()
        destination = ROOT / '.cache/ci-selection.json'
        destination.parent.mkdir(exist_ok=True)
        destination.write_bytes(encoded)
        print(json.dumps({'full': value['full'], 'flags': value['flags'],
                          'counts': {key: len(paths) for key, paths in value['files'].items()}}, indent=2))
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
                print('selection=' + hashlib.sha256(encoded).hexdigest(), file=output)
                for key, flag in value['flags'].items():
                    print(key + '=' + str(flag).lower(), file=output)
        return 0
    raw = (ROOT / '.cache/ci-selection.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != os.environ['CI_SELECTION_SHA256']:
        raise ValueError('CI selection artifact does not match the planner output')
    value = validate(json.loads(raw))
    if args.action == 'aggregate':
        aggregate(value, json.loads(os.environ['CI_NEEDS']))
        print('Every selected check passed; inapplicable checks were skipped.')
        return 0
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise ValueError('No Make target provided')
    environment = dict(os.environ)
    for name in ('AFFECTED', 'MAKEFLAGS', 'MFLAGS', 'MAKELEVEL', 'MAKEFILES', 'MAKEOVERRIDES', 'GNUMAKEFLAGS'):
        environment.pop(name, None)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', suffix='.mk',
                                     prefix='ci-selection-', dir=ROOT / '.cache') as selection:
        selection.write(selection_makefile(value, command))
        selection.flush()
        return subprocess.call(make_command(value, command, selection.name), cwd=ROOT, env=environment)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyError, TypeError, ValueError, OSError, UnicodeError) as error:
        print('CI scope error: ' + str(error), file=sys.stderr)
        sys.exit(1)
