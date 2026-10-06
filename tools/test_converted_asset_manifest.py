# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Offline tests for complete converted-asset provenance and cache controls."""

import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_converted_asset_manifest as check


class ManifestTests(unittest.TestCase):
    def test_local_hashes_source_pins_and_synthetic_reproductions(self):
        with patch.object(check, 'urlopen', side_effect=AssertionError('offline')):
            self.assertEqual(check.verify(), [])
            self.assertEqual(check.verify(require_source_pins=True), [])

    def test_manifest_drift_is_refused(self):
        original = json.loads(check.MANIFEST.read_text())
        cases = []
        for registry in ('production_assets', 'synthetic_regeneration'):
            data = copy.deepcopy(original)
            data[registry] = []
            cases.append((data, 'registry'))
            data = copy.deepcopy(original)
            data[registry][0] = copy.deepcopy(data[registry][1])
            cases.append((data, 'registry'))
        for key, value, error in [('schema_version', 1, 'schema'),
                                  ('status', 'unverified', 'status')]:
            data = copy.deepcopy(original)
            data[key] = value
            cases.append((data, error))
        data = copy.deepcopy(original)
        data['files'][next(iter(data['files']))] = '0' * 64
        cases.append((data, 'hash mismatch'))
        for path in check.REQUIRED_FILES:
            data = copy.deepcopy(original)
            del data['files'][path]
            cases.append((data, 'need recorded hashes'))
        for key, value, error in [('converter', 'wrong', 'converter binding'),
                                 ('source', {}, 'source binding'),
                                 ('parameters', {}, 'parameter'),
                                 ('format_version', 0, 'format version'),
                                 ('output_size_bytes', 0, 'output size'),
                                 ('regeneration_verified', False, 'regeneration')]:
            data = copy.deepcopy(original)
            data['production_assets'][0][key] = value
            cases.append((data, error))
        for key, value, error in [('spdx', 'wrong', 'license'),
                                 ('source_files', [], 'license evidence'),
                                 ('source_files', ['FaceXModel/jawOpen.obj'], 'license evidence'),
                                 ('evidence_urls', True, 'license evidence'),
                                 ('evidence_urls', ['not a URL'], 'license evidence')]:
            data = copy.deepcopy(original)
            data['production_assets'][0]['license'][key] = value
            cases.append((data, error))
        for name in check.SOURCE_EVIDENCE:
            data = copy.deepcopy(original)
            data['sources'][name]['files'] = [entry for entry in data['sources'][name]['files']
                                              if entry['role'] == 'input']
            cases.append((data, 'license/context evidence'))
            data = copy.deepcopy(original)
            evidence = next(e for e in data['sources'][name]['files'] if e['role'] != 'input')
            evidence['role'] = 'context' if evidence['role'] == 'license' else 'license'
            cases.append((data, 'license/context evidence'))
        for key, value, error in [('revision', 'main', 'immutable commit'),
                                 ('repository', 'https://example.com', 'repository binding'),
                                 ('files', [], 'Missing source files')]:
            data = copy.deepcopy(original)
            data['sources']['ict'][key] = value
            cases.append((data, error))
        for key, value, error in [('sha256', None, 'checksum'),
                                 ('git_blob_sha1', 'bad', 'checksum'),
                                 ('size_bytes', True, 'source size'),
                                 ('size_bytes', 17000000, 'source size'),
                                 ('role', 'executable', 'source role'),
                                 ('path', '../outside', 'manifest path'),
                                 ('path', '/absolute', 'manifest path'),
                                 ('path', 'a/./b', 'manifest path')]:
            data = copy.deepcopy(original)
            data['sources']['ict']['files'][0][key] = value
            cases.append((data, error))
        data = copy.deepcopy(original)
        data['sources']['ict']['files'].append(data['sources']['ict']['files'][0])
        cases.append((data, 'Duplicate source'))
        data = copy.deepcopy(original)
        data['sources']['ict']['files'].pop(0)
        cases.append((data, 'ICT input set'))
        data = copy.deepcopy(original)
        data['sources']['sintel']['files'][-1]['path'] = 'wrong.tfx'
        cases.append((data, 'Hair input binding'))
        for field in ('format', 'source'):
            data = copy.deepcopy(original)
            data['synthetic_regeneration'][1][field] = 'unrecognized'
            cases.append((data, 'binding'))
        for key, value in [('output_sha256', '0' * 64), ('output_size_bytes', 1)]:
            data = copy.deepcopy(original)
            data['synthetic_regeneration'][0][key] = value
            cases.append((data, 'regeneration mismatch'))
        data = copy.deepcopy(original)
        data['synthetic_regeneration'][1]['decoded_input_sha256'] = '0' * 64
        cases.append((data, 'Decoded synthetic source'))
        for data in ({}, [], None, {'schema_version': 2}, {'schema_version': 2, 'status': []}):
            cases.append((data, 'Malformed|status'))
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / 'manifest.json'
            for data, error in cases:
                with self.subTest(error=error):
                    manifest.write_text(json.dumps(data))
                    with self.assertRaisesRegex(ValueError, error):
                        check.verify(manifest=manifest)

    def test_fetch_needs_explicit_cache(self):
        with self.assertRaisesRegex(ValueError, 'explicit --source-cache'):
            check.verify(fetch_sources=True)

    @staticmethod
    def cache_manifest(content=b'pinned source'):
        return {'sources': {'fixture': {
            'repository': 'https://github.com/USC-ICT/ICT-FaceKit', 'revision': 'a' * 40,
            'files': [{'path': 'input.obj', 'role': 'input', 'size_bytes': len(content),
                       'sha256': hashlib.sha256(content).hexdigest(),
                       'git_blob_sha1': hashlib.sha1(f'blob {len(content)}\0'.encode() + content).hexdigest()}]}}}

    def test_cache_missing_wrong_revision_altered_and_extra_files(self):
        data = self.cache_manifest()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            cache = root / 'cache'
            source = cache / 'fixture' / ('a' * 40) / 'input.obj'
            with patch.object(check, 'urlopen', side_effect=AssertionError('offline')):
                with self.assertRaisesRegex(ValueError, 'Missing pinned source'):
                    check.materialize_sources(data, cache, root / 'staged')
                wrong = cache / 'fixture' / ('b' * 40) / 'input.obj'
                wrong.parent.mkdir(parents=True)
                wrong.write_bytes(b'pinned source')
                with self.assertRaisesRegex(ValueError, 'Missing pinned source'):
                    check.materialize_sources(data, cache, root / 'staged')
                source.parent.mkdir(parents=True)
                source.write_bytes(b'altered bytes')
                with self.assertRaisesRegex(ValueError, 'checksum or size'):
                    check.materialize_sources(data, cache, root / 'staged', fetch=True)
                self.assertEqual(source.read_bytes(), b'altered bytes')
                source.write_bytes(b'pinned source')
                (source.parent / 'extra.obj').write_bytes(b'must not be consumed')
                check.materialize_sources(data, cache, root / 'staged')
                self.assertEqual((root / 'staged/fixture/input.obj').read_bytes(), b'pinned source')
                self.assertFalse((root / 'staged/fixture/extra.obj').exists())

    def test_explicit_fetch_checks_bytes_and_uses_immutable_url(self):
        data = self.cache_manifest()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'cache/fixture' / ('a' * 40) / 'input.obj'
            with patch.object(check, 'urlopen', return_value=io.BytesIO(b'wrong')):
                with self.assertRaisesRegex(ValueError, 'checksum or size'):
                    check.materialize_sources(data, root / 'cache', root / 'stage', True)
            self.assertFalse(path.exists())
            with patch.object(check, 'urlopen', return_value=io.BytesIO(b'pinned source')) as fetch:
                check.materialize_sources(data, root / 'cache', root / 'stage', True)
                fetch.assert_called_once_with('https://raw.githubusercontent.com/USC-ICT/ICT-FaceKit/' +
                                              'a' * 40 + '/input.obj', timeout=60)
            with patch.object(check, 'urlopen', side_effect=AssertionError('reuse cache')):
                check.materialize_sources(data, root / 'cache', root / 'stage', True)
            self.assertEqual(path.read_bytes(), b'pinned source')

    def test_symlink_cannot_escape_cache(self):
        data = self.cache_manifest()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'cache').mkdir()
            (root / 'outside').mkdir()
            (root / 'cache/fixture').symlink_to(root / 'outside', target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'escapes cache'):
                check.materialize_sources(data, root / 'cache', root / 'stage', True)

    def test_production_match_and_mismatch_never_replace_accepted_outputs(self):
        data = {'production_assets': [{'path': 'assets/hair/layered.bin',
                 'source': {'id': 'sintel', 'input': 'input.tfx'},
                 'parameters': {'style': 'layered'}, 'output_size_bytes': 8}],
                'files': {'assets/hair/layered.bin': hashlib.sha256(b'accepted').hexdigest()}}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            accepted = root / 'assets/hair/layered.bin'
            accepted.parent.mkdir(parents=True)
            accepted.write_bytes(b'accepted')
            (root / 'scratch').mkdir()
            def convert(style, source, target):
                Path(target).write_bytes(b'accepted')
            with patch.object(check.hair_style, 'convert', side_effect=convert):
                check.regenerate_production(data, root / 'source', root / 'scratch')
            data['files']['assets/hair/layered.bin'] = '0' * 64
            with patch.object(check.hair_style, 'convert', side_effect=convert):
                with self.assertRaisesRegex(ValueError, 'Production regeneration mismatch'):
                    check.regenerate_production(data, root / 'source', root / 'scratch')
            self.assertEqual(accepted.read_bytes(), b'accepted')


if __name__ == '__main__':
    unittest.main()
