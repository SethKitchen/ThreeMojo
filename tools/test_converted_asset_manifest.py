# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for the converted-asset evidence check and synthetic reproduction."""

import copy
import json
from pathlib import Path
import tempfile
import unittest

import check_converted_asset_manifest as check


class ManifestTests(unittest.TestCase):
    def test_local_hashes_and_all_synthetic_reproductions(self):
        self.assertEqual(len(check.verify()), 3)

    def test_missing_production_pins_remain_a_failure(self):
        with self.assertRaisesRegex(ValueError, 'Historical source pins are unverified'):
            check.verify(require_source_pins=True)

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
        data = copy.deepcopy(original)
        data['schema_version'] = 2
        cases.append((data, 'schema'))
        data = copy.deepcopy(original)
        data['files'][next(iter(data['files']))] = '0' * 64
        cases.append((data, 'hash mismatch'))
        for field, value in [('status', 'verified'), ('revision', 'pretend'),
                             ('sha256', '0' * 64)]:
            data = copy.deepcopy(original)
            data['production_assets'][0]['source'][field] = value
            cases.append((data, 'Historical|Unverified'))
        for field, value in [('regeneration_verified', True), ('output_size_bytes', 0)]:
            data = copy.deepcopy(original)
            data['production_assets'][0][field] = value
            cases.append((data, 'Historical regeneration|output size'))
        for path in check.REQUIRED_FILES:
            data = copy.deepcopy(original)
            del data['files'][path]
            cases.append((data, 'need recorded hashes'))
        data = copy.deepcopy(original)
        data['production_assets'][0]['converter'] = data['production_assets'][0]['path']
        cases.append((data, 'converter binding'))
        for field in ('format', 'source'):
            data = copy.deepcopy(original)
            data['synthetic_regeneration'][1][field] = 'unrecognized'
            cases.append((data, 'binding'))
        data = copy.deepcopy(original)
        data['synthetic_regeneration'][0]['output_sha256'] = '0' * 64
        cases.append((data, 'regeneration mismatch'))
        data = copy.deepcopy(original)
        data['synthetic_regeneration'][1]['decoded_input_sha256'] = '0' * 64
        cases.append((data, 'Decoded synthetic source'))
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / 'manifest.json'
            for data, error in cases:
                with self.subTest(error=error):
                    manifest.write_text(json.dumps(data))
                    with self.assertRaisesRegex(ValueError, error):
                        check.verify(manifest=manifest)


if __name__ == '__main__':
    unittest.main()
