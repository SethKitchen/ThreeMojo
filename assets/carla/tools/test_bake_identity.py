# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Far-bake identities need only the standard library, not CARLA or NumPy."""

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from export.bake_identity import BakeIdentity


class BakeIdentityTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        (self.root / 'red.png').write_bytes(b'red pixels')
        (self.root / 'green.png').write_bytes(b'green pixels')
        self.gltf = {
            'materials': [
                {'name': 'red', 'pbrMetallicRoughness': {
                    'baseColorFactor': [1, 1, 1, 1], 'baseColorTexture': {'index': 0}}},
                {'name': 'green', 'pbrMetallicRoughness': {
                    'baseColorFactor': [1, 1, 1, 1], 'baseColorTexture': {'index': 1}}}],
            'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}],
            'images': [{'uri': 'red.png'}, {'uri': 'green.png'}],
            'samplers': [{'wrapS': 10497, 'wrapT': 10497}],
        }

    def key(self, gltf=None, parts=None, kind='baked', settings=None):
        return BakeIdentity(gltf or self.gltf, self.root).key(
            '/Game/Fixture', kind, parts or [('left', 0), ('right', 1)],
            {'samples': 4} if settings is None else settings)

    def test_order_duplicates_geometry_and_kind_are_part_of_identity(self):
        original = self.key()
        variants = [self.key(parts=[('left', 1), ('right', 0)]),
                    self.key(parts=[('right', 1), ('left', 0)]),
                    self.key(parts=[('left', 0)]),
                    self.key(parts=[('left', 0), ('left', 0)]),
                    self.key(parts=[('changed', 0), ('right', 1)]),
                    self.key(kind='impostor'), self.key(settings={'samples': 8})]
        self.assertNotIn(original, variants)
        self.assertEqual(original, self.key())
        self.assertRegex(original, r'^baked_[0-9a-f]{64}$')

    def test_identity_version_changes_atlas_names(self):
        original = self.key()
        with mock.patch('export.bake_identity._IDENTITY_VERSION', 2):
            self.assertNotEqual(original, self.key())

    def test_resolved_parameters_are_all_retained(self):
        original = self.key()
        changes = [
            lambda m: m.update(alphaMode='MASK'),
            lambda m: m.update(alphaCutoff=0.25),
            lambda m: m.update(doubleSided=True),
            lambda m: m['pbrMetallicRoughness'].update(baseColorFactor=[0.5, 1, 1, 0.5]),
            lambda m: m['pbrMetallicRoughness'].update(roughnessFactor=0.2),
            lambda m: m['pbrMetallicRoughness']['baseColorTexture'].update(texCoord=1),
            lambda m: m.update(normalTexture={'index': 1, 'scale': 0.5}),
            lambda m: m.update(extensions={'fixture': {'detailTexture': {'index': 1}}}),
        ]
        for change in changes:
            with self.subTest(change=change):
                gltf = copy.deepcopy(self.gltf)
                change(gltf['materials'][0])
                self.assertNotEqual(original, self.key(gltf))
        gltf = copy.deepcopy(self.gltf)
        gltf['samplers'][0]['wrapS'] = 33071
        self.assertNotEqual(original, self.key(gltf))

    def test_dictionary_order_and_table_indices_do_not_change_identity(self):
        gltf = json.loads(json.dumps(self.gltf, sort_keys=True))
        gltf['materials'].reverse()
        gltf['textures'].reverse()
        gltf['images'].reverse()
        gltf['samplers'].insert(0, {'unused': True})
        for material in gltf['materials']:
            info = material['pbrMetallicRoughness']['baseColorTexture']
            info['index'] = 1 - info['index']
        for texture in gltf['textures']:
            texture['source'] = 1 - texture['source']
            texture['sampler'] = 1
        self.assertEqual(self.key(), self.key(gltf, [('left', 1), ('right', 0)]))

    def test_texture_content_changes_identity_between_builds(self):
        original = self.key()
        (self.root / 'red.png').write_bytes(b'new pixels at the same path')
        self.assertNotEqual(original, self.key())

    def test_output_root_and_python_hash_seed_do_not_enter_identity(self):
        with tempfile.TemporaryDirectory() as other:
            for name in ('red.png', 'green.png'):
                (Path(other) / name).write_bytes((self.root / name).read_bytes())
            self.assertEqual(self.key(), BakeIdentity(self.gltf, other).key(
                '/Game/Fixture', 'baked', [('left', 0), ('right', 1)], {'samples': 4}))
        # A fixed value also catches accidental use of hash(), repr() or
        # unframed concatenation when the interpreter's hash seed changes.
        simple = BakeIdentity({'materials': [{'base': [1, 2, 3]}]}, self.root)
        self.assertEqual(simple.key('mesh', 'baked', [('shape', 0)], {}),
                         'baked_b3697ccb0e157a5f8aeba3bc58f0949dc000188f799d294396c65ea585779432')

    def test_hashes_shared_images_once_per_build(self):
        gltf = copy.deepcopy(self.gltf)
        gltf['materials'][1]['pbrMetallicRoughness']['baseColorTexture']['index'] = 0
        cache = BakeIdentity(gltf, self.root)
        with mock.patch('builtins.open', wraps=open) as reads:
            keys = [cache.key('mesh', 'baked', [('a', 0), ('b', 1)], {}) for _ in range(5)]
        self.assertEqual(reads.call_count, 1)
        self.assertEqual(len(set(keys)), 1)

    def test_texture_without_sampler_keeps_its_default_and_metadata(self):
        gltf = copy.deepcopy(self.gltf)
        for texture in gltf['textures']:
            texture.pop('sampler')
        gltf['materials'][0]['extraTexture'] = None
        gltf['materials'][0]['extensions'] = {'fixture': {'unusedTexture': {}}}
        self.assertEqual(self.key(gltf), self.key(copy.deepcopy(gltf)))
        gltf['images'][0]['mimeType'] = 'image/png'
        self.assertNotEqual(self.key(gltf), self.key())

    def test_factors_without_textures_need_no_files(self):
        gltf = {'materials': [{'pbrMetallicRoughness': {'baseColorFactor': [1, 0, 0, 1]}}]}
        with mock.patch('builtins.open', side_effect=AssertionError('unexpected file read')):
            self.assertRegex(self.key(gltf, [('shape', 0)]), r'^baked_[0-9a-f]{64}$')

    def test_missing_texture_and_nonfinite_parameters_fail_clearly(self):
        (self.root / 'red.png').unlink()
        with self.assertRaises(FileNotFoundError):
            self.key()
        with self.assertRaises(ValueError):
            self.key({'materials': [{'factor': float('nan')}]}, [('shape', 0)])


if __name__ == '__main__':
    unittest.main()
