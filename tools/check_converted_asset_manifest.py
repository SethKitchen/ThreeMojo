# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Verify converted asset hashes and regenerate small pinned synthetic inputs.

Run from any directory. This does not fetch assets, edit accepted outputs, or
certify the unavailable historical inputs of the bundled production models.
"""

import argparse
import hashlib
import json
from pathlib import Path
import tempfile

import hair_style
import ict_face_model

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'assets/converted-asset-manifest.json'
PRODUCTION = {
    'assets/face/ict_face.bin': 'tools/ict_face_model.py',
    'assets/hair/layered.bin': 'tools/hair_style.py',
    'assets/hair/mohawk.bin': 'tools/hair_style.py',
}
SYNTHETIC = {
    'small-face': ('ICTF', 'assets/converted-fixtures/face'),
    'small-layered': ('THRS', 'assets/converted-fixtures/layered.tfx.hex'),
    'small-mohawk': ('THRS', 'assets/converted-fixtures/mohawk.tfx.hex'),
}
REQUIRED_FILES = set(PRODUCTION) | set(PRODUCTION.values()) | {
    'assets/converted-fixtures/face/' + name for name in (
        'generic_neutral_mesh.obj', 'identity000.obj', 'jawOpen.obj', 'still.obj')
} | {SYNTHETIC[name][1] for name in ('small-layered', 'small-mohawk')}


def digest(path):
    """Return the SHA-256 of a local file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root=ROOT, manifest=MANIFEST, require_source_pins=False):
    """Verify all recorded bytes and reproduce the small synthetic outputs.

    Raises ValueError on drift, or when required historical pins are missing.
    """
    data = json.loads(manifest.read_text())
    if data['schema_version'] != 1:
        raise ValueError('Unsupported converted asset manifest schema')
    production = [entry['path'] for entry in data['production_assets']]
    synthetic = [entry['name'] for entry in data['synthetic_regeneration']]
    if len(production) != 3 or set(production) != set(PRODUCTION):
        raise ValueError('The production asset registry must contain all three assets')
    if len(synthetic) != 3 or set(synthetic) != set(SYNTHETIC):
        raise ValueError('The synthetic registry must contain all three fixtures')
    if not REQUIRED_FILES <= set(data['files']):
        raise ValueError('All production, converter and synthetic inputs need recorded hashes')
    for path, expected in data['files'].items():
        if digest(root / path) != expected:
            raise ValueError(f'Converted asset manifest hash mismatch: {path}')
    missing = []
    for entry in data['production_assets']:
        if entry['converter'] != PRODUCTION[entry['path']]:
            raise ValueError('Production converter binding mismatch')
        if (root / entry['path']).stat().st_size != entry['output_size_bytes']:
            raise ValueError('Production output size mismatch')
        if entry['regeneration_verified'] is not False:
            raise ValueError('Historical regeneration remains unverified')
        if entry['source']['status'] != 'unverified':
            raise ValueError('Historical source verification needs new evidence')
        if entry['source']['revision'] is not None or entry['source']['sha256'] is not None:
            raise ValueError('Unverified historical sources must not claim pins')
        missing.append(entry['path'])
    with tempfile.TemporaryDirectory(prefix='converted-asset-check-') as folder:
        tmp = Path(folder)
        for entry in data['synthetic_regeneration']:
            if (entry['format'], entry['source']) != SYNTHETIC[entry['name']]:
                raise ValueError('Synthetic format or source binding mismatch')
            target = tmp / 'out.bin'
            if entry['format'] == 'ICTF':
                ict_face_model.convert(str(root / entry['source']), str(target),
                                       **entry['parameters'])
            else:
                source = tmp / 'source.tfx'
                source.write_bytes(bytes.fromhex((root / entry['source']).read_text()))
                if digest(source) != entry['decoded_input_sha256']:
                    raise ValueError('Decoded synthetic source hash mismatch')
                hair_style.convert(entry['parameters']['style'], str(source), str(target))
            if digest(target) != entry['output_sha256']:
                raise ValueError(f'Synthetic regeneration mismatch: {entry["name"]}')
    if require_source_pins and missing:
        raise ValueError('Historical source pins are unverified: ' + ', '.join(missing))
    return missing


def main():
    """Check local bytes; optionally require complete production provenance."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-source-pins', action='store_true')
    args = parser.parse_args()
    try:
        missing = verify(require_source_pins=args.require_source_pins)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
    print('Verified recorded hashes and three synthetic converter outputs.')
    print('Production upstream inputs remain unverified: ' + ', '.join(missing))


if __name__ == '__main__':
    main()
