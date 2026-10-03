# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the recorded three.js fixture baselines without running generators."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path('assets/fixture-manifest.json')
RUNTIME_PACKAGES = Path('tools/fixture-runtime')
VERIFIED_FAMILIES = {'vtk', 'js_number'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime_metadata_errors(root, family):
    """Require exact pins and guarded commands for verified runtime families."""
    name = family.get('family')
    if name not in VERIFIED_FAMILIES:
        return []
    baseline = family.get('verified_runtime', {})
    errors = []
    for key, pattern in [('node', r'\d+\.\d+\.\d+'),
                         ('v8', r'\d+\.\d+\.\d+\.\d+-node\.\d+')]:
        if not re.fullmatch(pattern, str(baseline.get(key, ''))):
            errors.append(f'{name}: verified {key} must be exact')
    if baseline.get('platform') != 'linux' or baseline.get('arch') != 'x64':
        errors.append(f'{name}: verified platform must remain linux/x64')
    flags = ['--no-use-std-math-pow'] if name == 'js_number' else []
    if baseline.get('node_flags') != flags:
        errors.append(f'{name}: verified Node flags differ')
    if baseline.get('historical_environment_recovered') is not False:
        errors.append(f'{name}: do not infer historical runtime provenance')
    if not baseline.get('evidence'):
        errors.append(f'{name}: missing runtime evidence')
    dependencies = baseline.get('dependencies', {})
    required = {'three', '@xmldom/xmldom'} if name == 'vtk' else {'three'}
    if set(dependencies) != required:
        errors.append(f'{name}: verified dependencies differ')
    for package, version in dependencies.items():
        if not re.fullmatch(r'\d+\.\d+\.\d+', str(version)):
            errors.append(f'{name}: {package} must be exact')
    expected_commands = [
        'npm ci --ignore-scripts --prefix tools/fixture-runtime',
        f'python3 tools/fixture_runtime.py {name}',
    ]
    if family.get('cwd') != '.' or family.get('commands') != expected_commands:
        errors.append(f'{name}: use the pinned, guarded fixture commands')
    try:
        package = json.loads((root / RUNTIME_PACKAGES / 'package.json').read_text())
        lock = json.loads((root / RUNTIME_PACKAGES / 'package-lock.json').read_text())
        if package.get('engines', {}).get('node') != baseline.get('node'):
            errors.append(f'{name}: package Node pin differs')
        if lock['packages'][''].get('engines') != package.get('engines'):
            errors.append(f'{name}: lockfile Node pin differs')
        if lock['packages'][''].get('dependencies') != package.get('dependencies'):
            errors.append(f'{name}: lockfile dependency pins differ')
        for dependency, version in dependencies.items():
            entry = lock['packages'][f'node_modules/{dependency}']
            if (package['dependencies'].get(dependency) != version
                    or entry.get('version') != version or not entry.get('integrity')):
                errors.append(f'{name}: {dependency} package/lock pin differs')
    except (OSError, ValueError, KeyError) as error:
        errors.append(f'{name}: cannot check runtime package pins: {error}')
    if name == 'js_number':
        snapshot = family.get('separate_snapshot', {})
        if (family.get('three_version') is not None
                or not {'generator', 'historical_node', 'historical_v8'} <= snapshot.keys()
                or snapshot.get('historical_node_major') != 22
                or snapshot.get('path') != 'assets/js_number/v8.json'
                or snapshot.get('status') != 'not_regenerated'
                or snapshot.get('generator') is not None
                or snapshot.get('historical_node') is not None
                or snapshot.get('historical_v8') is not None
                or not snapshot.get('evidence')):
            errors.append(f'{name}: keep the separate V8 snapshot provenance explicit')
    return errors


def check(root, manifest):
    """Return drift and metadata errors; never update the accepted hashes."""
    errors = []
    recorded = set()
    for family in manifest['families']:
        generator = family['generator']
        if generator in recorded:
            errors.append(f'duplicate generator: {generator}')
        recorded.add(generator)
        version = family['three_version']
        if version is not None and not re.fullmatch(r'\d+\.\d+\.\d+', version):
            errors.append(f'{generator}: three_version must be exact')
        if not family.get('version_evidence') or not family.get('commands'):
            errors.append(f'{generator}: missing provenance or commands')
        errors.extend(runtime_metadata_errors(root, family))
        files = {generator: family['generator_sha256'], **family['artifacts']}
        for name, expected in files.items():
            path = root / name
            if not path.is_file():
                errors.append(f'missing: {name}')
            elif digest(path) != expected:
                errors.append(f'changed: {name}')
    actual = {p.relative_to(root).as_posix() for p in (root / 'assets').rglob('*.mjs')
              if 'node_modules' not in p.parts}
    for name in sorted(actual ^ recorded):
        errors.append(f'generator inventory differs: {name}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commands', metavar='FAMILY', help='show the recorded manual regeneration steps')
    args = parser.parse_args()
    manifest = json.loads((ROOT / MANIFEST).read_text())
    if args.commands:
        for family in manifest['families']:
            if family['family'] == args.commands:
                print('cwd:', family['cwd'])
                print('\n'.join(family['commands']))
                for note in family.get('notes', []):
                    print('Note:', note)
                return 0
        parser.error('unknown family')
    errors = check(ROOT, manifest)
    for error in errors:
        print(error)
    if not errors:
        print(f"Checked {len(manifest['families'])} fixture families; hashes match.")
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
