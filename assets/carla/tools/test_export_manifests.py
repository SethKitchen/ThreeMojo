# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Regenerate package families without keeping dangling asset bindings."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

import carla_assets as tool
from export import manifest_towns, manifest_vehicles


class ExportManifestTests(unittest.TestCase):
    def replace_family(self, module, ids, packages, keys):
        for retain in (1, 0):
            with self.subTest(module=module.__name__, retain=retain), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                entries = [module.entry_of(identifier, packages[identifier],
                                           'https://example.org/' + identifier + '.zip')
                           for identifier in ids]
                unrelated = {
                    'id': 'unrelated', 'kind': 'model', 'forward': '+x',
                    'license': 'CC0-1.0', 'author': 'Test',
                    'source': 'https://example.org/model', 'provenance': 'Fixture only.',
                    'files': [{'role': 'model', 'path': 'unrelated.glb', 'url': None, 'sha256': 'a' * 64}],
                }
                bindings = {key: entry['id'] for key, entry in zip(keys, entries)}
                prefix = 'town.' if module is manifest_towns else 'vehicle.'
                bindings.update({prefix + 'alias_kept': entries[0]['id'],
                                 prefix + 'alias_removed': entries[1]['id'],
                                 'prop.unrelated': 'unrelated'})
                original = {'format': 1, 'entries': entries + [unrelated], 'bindings': bindings}
                path = root / 'manifest.json'
                tool.save_manifest(original, path)
                index = root / 'index.json'
                index.write_text(json.dumps({identifier: packages[identifier] for identifier in ids[:retain]}))
                with redirect_stdout(io.StringIO()):
                    module.main(['--manifest', str(path), '--index', str(index)])
                result = tool.load_manifest(path)
                kept = {entry['id']: entry for entry in result['entries']}
                self.assertEqual(kept['unrelated'], unrelated)
                self.assertEqual(set(kept), {'unrelated'} | {entry['id'] for entry in entries[:retain]})
                for key, value in bindings.items():
                    self.assertEqual(result['bindings'][key], value if value in kept else None)
                if retain:
                    self.assertEqual(kept[entries[0]['id']]['files'][0]['url'], entries[0]['files'][0]['url'])

    def test_vehicle_removal_clears_only_bindings_to_removed_entries(self):
        ids = ['vehicle.audi.a2', 'vehicle.tesla.model3']
        packages = {identifier: {'zip': identifier + '.zip', 'sha256': 'a' * 64,
                                 'members': [identifier + '.gltf']} for identifier in ids}
        self.replace_family(manifest_vehicles, ids, packages, ids)

    def test_town_removal_clears_only_bindings_to_removed_entries(self):
        ids = ['carla.town.town01', 'carla.town.town02']
        packages = {identifier: {'zip': identifier + '.zip', 'sha256': 'a' * 64,
                                 'members': [identifier + '.glb', f'Town0{index + 1}.xodr']}
                    for index, identifier in enumerate(ids)}
        self.replace_family(manifest_towns, ids, packages, ['town.Town01', 'town.Town02'])


if __name__ == '__main__':
    unittest.main()
