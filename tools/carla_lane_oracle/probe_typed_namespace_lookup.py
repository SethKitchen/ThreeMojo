#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bounded pinned-compiler lookup witness for the newly bound #333 families.

Run only in the exclusive compiler lane with the official --mojo executable.
Generated sources/binaries stay below --workspace. This is separate compiler
qualification, never a runtime proof-gate cache or an admission adapter.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

FAMILIES = ('animation', 'cameras', 'core', 'exporters', 'geometries',
            'lights', 'materials', 'objects', 'postprocessing', 'renderers')


def write(root, relative, text):
    path = root/relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def providers(root, prefix, value):
    for family in FAMILIES:
        write(root, prefix + family + '/__init__.mojo', '# lookup fixture\n')
        write(root, prefix + family + '/probe.mojo',
              'def marker() -> Int:\n    return ' + str(value) + '\n')


def reader(prefix=''):
    imports = ''.join('from ' + prefix + family + '.probe import marker as marker_' + family + '\n'
                      for family in FAMILIES)
    return imports + '\ndef total() -> Int:\n    return ' + ' + '.join(
        'marker_' + family + '()' for family in FAMILIES) + '\n'


def entry(expected):
    return ('from library.reader import total\n\ndef main() raises:\n'
            '    if total() != ' + str(expected) + ':\n'
            '        raise Error("unexpected namespace lookup")\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    if workspace.exists():
        raise ValueError('workspace must be a new isolated directory')
    workspace.mkdir(parents=True)
    version = subprocess.run([str(args.mojo), '--version'], check=True,
                             capture_output=True, text=True, timeout=10)
    if '1.1.0' not in version.stdout + version.stderr:
        raise ValueError('lookup witness requires pinned Mojo 1.1.0')
    results = []
    for case in ('root', 'missing_root', 'entry_package', 'entry_prefix_module',
                 'new_asset_entry', 'explicit_asset_import'):
        root = workspace/case
        root.mkdir()
        providers(root, '', 17)
        providers(root, 'library/', 97)
        providers(root, 'assets/', 99)
        write(root, 'library/__init__.mojo', '# library fixture\n')
        write(root, 'library/reader.mojo', reader('assets.' if case == 'explicit_asset_import' else ''))
        expected, location, success = 170, 'tools/entry.mojo', True
        if case == 'missing_root':
            for family in FAMILIES:
                shutil.move(str(root/family), str(workspace/(case + '-removed-' + family)))
            success = False
        elif case == 'entry_package':
            providers(root, 'tools/', 23)
            expected = 230
        elif case == 'entry_prefix_module':
            for family in FAMILIES:
                write(root, 'tools/' + family + '.mojo', '# hides root package\n')
            success = False
        elif case == 'new_asset_entry':
            location, expected = 'assets/entry.mojo', 990
        elif case == 'explicit_asset_import':
            expected = 990
        write(root, location, entry(expected))
        started = time.monotonic()
        build = subprocess.run([str(args.mojo), 'build', '--num-threads', '1', '--Werror',
            '-I', '.', location, '-o', 'probe'], cwd=root, capture_output=True, text=True, timeout=40)
        (root/'build.stdout').write_text(build.stdout)
        (root/'build.stderr').write_text(build.stderr)
        if (build.returncode == 0) != success:
            raise ValueError(case + ': unexpected compiler result: ' + build.stderr)
        if success:
            subprocess.run([str(root/'probe')], cwd=root, check=True, timeout=5)
        elif not any(word in build.stderr for word in ('unable to locate module', 'cannot find', 'unknown module')):
            raise ValueError(case + ': refusal did not identify module lookup: ' + build.stderr)
        result = {'case': case, 'status': 'PASS', 'expected_compilation': success,
                  'seconds': time.monotonic() - started, 'families': FAMILIES}
        results.append(result)
        print(json.dumps(result), flush=True)
    (workspace/'RESULT.json').write_text(json.dumps({
        'version': version.stdout + version.stderr, 'cases': results}, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
