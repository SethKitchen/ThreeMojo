# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check converted assets; optionally fetch and reproduce production sources.

The default check is offline and small. Production verification requires an
explicit --source-cache. Downloads also require --fetch-sources. Accepted
outputs and existing cache files are never replaced.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import tempfile
from urllib.request import urlopen

import hair_style
import ict_face_model

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'assets/converted-asset-manifest.json'
PRODUCTION = {
    'assets/face/ict_face.bin': ('tools/ict_face_model.py', 'ict', 'FaceXModel'),
    'assets/hair/layered.bin': ('tools/hair_style.py', 'sintel',
                             'static/models/SintelHairOriginal-sintel_hair.16points.tfx'),
    'assets/hair/mohawk.bin': ('tools/hair_style.py', 'ratboy',
                            'bin/Objects/HairAsset/Ratboy/Ratboy_mohawk.tfx'),
}
REPOSITORIES = {
    'ict': 'https://github.com/USC-ICT/ICT-FaceKit',
    'sintel': 'https://github.com/Scthe/frostbitten-hair-webgpu',
    'ratboy': 'https://github.com/GPUOpen-Effects/TressFX',
}
SOURCE_EVIDENCE = {
    'ict': {'LICENSE': 'license', 'README.md': 'context'},
    'sintel': {'README.md': 'context'},
    'ratboy': {'license.txt': 'license', 'README.md': 'context'},
}
SINTEL_LICENSE_URLS = [
    'https://blendswap.com/blend/2847',
    'https://durian.blender.org/about/',
    'https://creativecommons.org/licenses/by/3.0/',
]
SYNTHETIC = {
    'small-face': ('ICTF', 'assets/converted-fixtures/face'),
    'small-layered': ('THRS', 'assets/converted-fixtures/layered.tfx.hex'),
    'small-mohawk': ('THRS', 'assets/converted-fixtures/mohawk.tfx.hex'),
}
REQUIRED_FILES = set(PRODUCTION) | {v[0] for v in PRODUCTION.values()} | {
    'assets/converted-fixtures/face/' + name for name in (
        'generic_neutral_mesh.obj', 'identity000.obj', 'jawOpen.obj', 'still.obj')
} | {SYNTHETIC[name][1] for name in ('small-layered', 'small-mohawk')}


def digest(path):
    """Return the SHA-256 of a local file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _hex(value, length):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{%d}' % length, value) is not None


def _path(value):
    _require(isinstance(value, str) and value and '\\' not in value,
             'Invalid manifest path')
    path = PurePosixPath(value)
    _require(not path.is_absolute() and '..' not in path.parts and
             str(path) == value and value != '.', 'Invalid manifest path')
    return value


def _positive(value):
    return type(value) is int and value > 0


def _parameters(entry):
    """Require the complete recipe, including converter constants."""
    if entry['source']['id'] == 'ict':
        return {'identities': 60, 'skin_end': 11248, 'coarse_target': 6000,
                'to_meters': ict_face_model.TO_METERS,
                'still_meters': ict_face_model.STILL}
    result = {'style': 'layered' if entry['source']['id'] == 'sintel' else 'mohawk',
              'points': hair_style.POINTS, 'summation': 'left-to-right-binary64'}
    if result['style'] == 'mohawk':
        result.update(mohawk_from_degrees=hair_style.MOHAWK_FROM,
                      mohawk_to_degrees=hair_style.MOHAWK_TO,
                      scalp_from_degrees=hair_style.SCALP_FROM,
                      scalp_to_degrees=hair_style.SCALP_TO,
                      mohawk_head=hair_style.MOHAWK_HEAD,
                      mohawk_narrow=hair_style.MOHAWK_NARROW,
                      mohawk_reach=hair_style.MOHAWK_REACH,
                      human_radii=list(hair_style.HUMAN))
    return result


def validate(data, root):
    """Validate the manifest structure, source bindings and recorded local bytes."""
    try:
        _require(data['schema_version'] == 2, 'Unsupported converted asset manifest schema')
        _require(data['status'] == 'production-regeneration-verified', 'Unverified production status')
        production = [e['path'] for e in data['production_assets']]
        synthetic = [e['name'] for e in data['synthetic_regeneration']]
        _require(len(production) == 3 and set(production) == set(PRODUCTION),
                 'The production asset registry must contain all three assets')
        _require(len(synthetic) == 3 and set(synthetic) == set(SYNTHETIC),
                 'The synthetic registry must contain all three fixtures')
        _require(REQUIRED_FILES <= set(data['files']),
                 'All production, converter and synthetic inputs need recorded hashes')
        for path, expected in data['files'].items():
            _path(path)
            _require(_hex(expected, 64), 'Invalid local SHA-256')
            _require(digest(root / path) == expected,
                     f'Converted asset manifest hash mismatch: {path}')
        _require(set(data['sources']) == set(REPOSITORIES), 'Invalid source registry')
        for name, source in data['sources'].items():
            _require(source['repository'] == REPOSITORIES[name], 'Source repository binding mismatch')
            _require(_hex(source['revision'], 40), 'Source revision must be an immutable commit')
            _require(source['files'], 'Missing source files')
            paths = []
            for entry in source['files']:
                paths.append(_path(entry['path']))
                _require(_positive(entry['size_bytes']) and entry['size_bytes'] <= 16 * 1024 * 1024,
                         'Invalid source size')
                _require(_hex(entry['sha256'], 64) and _hex(entry['git_blob_sha1'], 40),
                         'Invalid source checksum')
                _require(entry['role'] in ('input', 'license', 'context'), 'Invalid source role')
            _require(len(paths) == len(set(paths)), 'Duplicate source file')
            evidence = {e['path']: e['role'] for e in source['files'] if e['role'] != 'input'}
            _require(evidence == SOURCE_EVIDENCE[name], 'Missing source license/context evidence')
            inputs = {e['path'] for e in source['files'] if e['role'] == 'input'}
            if name == 'ict':
                identities = {f'FaceXModel/identity{i:03d}.obj' for i in range(60)}
                _require(len(inputs) == 118 and identities <= inputs and
                         'FaceXModel/generic_neutral_mesh.obj' in inputs and
                         all(PurePosixPath(p).parent == PurePosixPath('FaceXModel') and
                             p.endswith('.obj') for p in inputs), 'Invalid ICT input set')
                expressions = inputs - identities - {'FaceXModel/generic_neutral_mesh.obj'}
                _require(all(not PurePosixPath(p).name.startswith(('identity', 'generic'))
                             for p in expressions), 'Invalid ICT expression set')
            else:
                expected = PRODUCTION['assets/hair/' + ('layered' if name == 'sintel' else 'mohawk') + '.bin'][2]
                _require(inputs == {expected}, 'Hair input binding mismatch')
        for entry in data['production_assets']:
            converter, source_id, source_input = PRODUCTION[entry['path']]
            _require(entry['converter'] == converter, 'Production converter binding mismatch')
            _require(entry['source'] == {'id': source_id, 'input': source_input},
                     'Production source binding mismatch')
            _require(entry['parameters'] == _parameters(entry), 'Production parameter mismatch')
            _require(entry['format_version'] == (ict_face_model.VERSION if source_id == 'ict' else hair_style.VERSION),
                     'Production format version mismatch')
            _require(entry['regeneration_verified'] is True, 'Unverified production regeneration')
            _require(_positive(entry['output_size_bytes']) and
                     (root / entry['path']).stat().st_size == entry['output_size_bytes'],
                     'Production output size mismatch')
            license = entry['license']
            _require(license['spdx'] == ('CC-BY-3.0' if source_id == 'sintel' else 'MIT'),
                     'Production license mismatch')
            source = data['sources'][source_id]
            source_files = list(SOURCE_EVIDENCE[source_id])
            urls = [source['repository'] + '/blob/' + source['revision'] + '/' + path
                    for path in source_files]
            if source_id == 'sintel':
                urls += SINTEL_LICENSE_URLS
            _require(license['source_files'] == source_files and
                     license['evidence_urls'] == urls and
                     license['notice'] == 'THIRD-PARTY-NOTICES.md',
                     'Missing license evidence')
        for entry in data['synthetic_regeneration']:
            _require((entry['format'], entry['source']) == SYNTHETIC[entry['name']],
                     'Synthetic format or source binding mismatch')
            _require(_hex(entry['output_sha256'], 64) and _positive(entry['output_size_bytes']),
                     'Invalid synthetic output pin')
    except (KeyError, TypeError, AttributeError) as error:
        raise ValueError('Malformed converted asset manifest') from error


def _check_source_bytes(content, entry):
    """Refuse changed, truncated or wrong-revision source bytes."""
    prefix = f'blob {len(content)}\0'.encode('ascii')
    _require(len(content) == entry['size_bytes'] and
             hashlib.sha256(content).hexdigest() == entry['sha256'] and
             hashlib.sha1(prefix + content).hexdigest() == entry['git_blob_sha1'],
             'Source checksum or size mismatch: ' + entry['path'])


def materialize_sources(data, cache, destination, fetch=False):
    """Check the explicit cache and stage exactly the pinned inputs.

    Fetch only missing files when requested. Never repair altered cache files.
    Each staged file is the same byte string that passed both checksum checks.
    """
    for name, source in data['sources'].items():
        base = cache / name / source['revision']
        for entry in source['files']:
            path = base / entry['path']
            _require(path.resolve().is_relative_to(cache.resolve()), 'Source path escapes cache')
            if not path.exists():
                _require(fetch, 'Missing pinned source: ' + str(path) +
                         '; use --fetch-sources with this explicit cache to download it')
                url = ('https://raw.githubusercontent.com/' + source['repository'].split('github.com/')[1]
                       + '/' + source['revision'] + '/' + entry['path'])
                with urlopen(url, timeout=60) as response:
                    content = response.read(entry['size_bytes'] + 1)
                _check_source_bytes(content, entry)
                path.parent.mkdir(parents=True, exist_ok=True)
                # Exclusive creation never replaces an existing cache file.
                try:
                    with path.open('xb') as target:
                        target.write(content)
                except FileExistsError:
                    pass
            with path.open('rb') as source_file:
                content = source_file.read(entry['size_bytes'] + 1)
            _check_source_bytes(content, entry)
            if entry['role'] == 'input':
                staged = destination / name / entry['path']
                staged.parent.mkdir(parents=True, exist_ok=True)
                staged.write_bytes(content)


def regenerate_production(data, sources, destination):
    """Reproduce all production files in scratch and compare accepted hashes."""
    for entry in data['production_assets']:
        source = sources / entry['source']['id'] / entry['source']['input']
        target = destination / Path(entry['path']).name
        parameters = entry['parameters']
        if entry['source']['id'] == 'ict':
            ict_face_model.convert(str(source), str(target), **{
                key: parameters[key] for key in ('identities', 'skin_end', 'coarse_target')})
        else:
            hair_style.convert(parameters['style'], str(source), str(target))
        _require(target.stat().st_size == entry['output_size_bytes'] and
                 digest(target) == data['files'][entry['path']],
                 'Production regeneration mismatch: ' + entry['path'])


def verify(root=ROOT, manifest=MANIFEST, require_source_pins=False,
           source_cache=None, fetch_sources=False):
    """Check pins and synthetic outputs; reproduce production only with a cache.

    The compatibility --require-source-pins option checks metadata. It does
    not imply that the production sources were available or converted today.
    """
    _require(not fetch_sources or source_cache is not None,
             '--fetch-sources requires an explicit --source-cache')
    try:
        data = json.loads(manifest.read_text(encoding='utf-8'))
        validate(data, root)
        with tempfile.TemporaryDirectory(prefix='converted-asset-check-') as folder:
            tmp = Path(folder)
            for entry in data['synthetic_regeneration']:
                target = tmp / 'out.bin'
                if entry['format'] == 'ICTF':
                    ict_face_model.convert(str(root / entry['source']), str(target),
                                           **entry['parameters'])
                else:
                    source = tmp / 'source.tfx'
                    source.write_bytes(bytes.fromhex((root / entry['source']).read_text()))
                    _require(digest(source) == entry['decoded_input_sha256'],
                             'Decoded synthetic source hash mismatch')
                    hair_style.convert(entry['parameters']['style'], str(source), str(target))
                _require(digest(target) == entry['output_sha256'] and
                         target.stat().st_size == entry['output_size_bytes'],
                         'Synthetic regeneration mismatch: ' + entry['name'])
            if source_cache is not None:
                materialize_sources(data, Path(source_cache), tmp / 'sources', fetch_sources)
                regenerate_production(data, tmp / 'sources', tmp)
    except (KeyError, TypeError, AttributeError) as error:
        raise ValueError('Malformed converted asset manifest') from error
    return []


def main():
    """Run an offline check or explicit production reproduction."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-source-pins', action='store_true',
                        help='require source metadata (also checked by default)')
    parser.add_argument('--source-cache', type=Path,
                        help='explicit local cache; enables full production reproduction')
    parser.add_argument('--fetch-sources', action='store_true',
                        help='download missing pinned inputs into the explicit cache')
    args = parser.parse_args()
    try:
        verify(require_source_pins=args.require_source_pins,
               source_cache=args.source_cache, fetch_sources=args.fetch_sources)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
    print('Verified local hashes, complete source pins, and three synthetic outputs.')
    if args.source_cache is None:
        print('Production reproduction was not run; pass --source-cache to check it.')
    else:
        print('Verified all pinned source bytes and reproduced all three production outputs exactly.')


if __name__ == '__main__':
    main()
