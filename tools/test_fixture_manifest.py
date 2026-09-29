# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""A fixture drift check must fail when inputs or provenance change."""
import json
from pathlib import Path
import tempfile
import unittest
from fixture_manifest import ROOT, MANIFEST, check, digest


class FixtureManifestTests(unittest.TestCase):
    def test_repository_matches_manifest(self):
        self.assertEqual(check(ROOT, json.loads((ROOT / MANIFEST).read_text())), [])

    def test_changed_missing_and_unlisted_files_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'assets').mkdir()
            generator = root / 'assets/generate.mjs'
            generator.write_text('original')
            fixture = root / 'assets/result.json'
            fixture.write_text('{}')
            manifest = {'families': [{
                'generator': 'assets/generate.mjs', 'three_version': '0.180.0',
                'version_evidence': 'generator header', 'commands': ['node generate.mjs'],
                'generator_sha256': digest(generator),
                'artifacts': {'assets/result.json': digest(fixture)},
            }]}
            self.assertEqual(check(root, manifest), [])
            fixture.write_text('[]')
            self.assertIn('changed: assets/result.json', check(root, manifest))
            fixture.unlink()
            self.assertIn('missing: assets/result.json', check(root, manifest))
            (root / 'assets/new.mjs').write_text('')
            self.assertIn('generator inventory differs: assets/new.mjs', check(root, manifest))
            manifest['families'][0]['three_version'] = '^0.180.0'
            self.assertTrue(any('must be exact' in error for error in check(root, manifest)))
