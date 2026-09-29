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


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
