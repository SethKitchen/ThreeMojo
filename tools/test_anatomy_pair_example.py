# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep the historical representative example pinned, separate from live evidence."""
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = ROOT / 'docs/validation/anatomy-pair-example.json'
SOURCE_COMMIT = '2c91d60c660d05cf5e0fa093e6774558ba14332f'
SOURCE_SHA256 = 'b3dd9ea15888167980fcff72e43e489d52f1106784c01d52ce9484fb7a36bc4d'
REPORT_SHA256 = 'c4b74bfa37670407512eedeac3601ce1d2fd670771143b78276ecac8add31f39'
PROBE_SHA256 = '752cbe627c526d4e2251d4c933f3eb051281bc5e9be32fd5565b943a56de5d30'


def check_metadata(report):
    provenance = report['build_provenance']
    if provenance['source_sha256'] != SOURCE_SHA256:
        raise ValueError('historical example source binding changed')
    if provenance['binary_sha256'] != PROBE_SHA256:
        raise ValueError('historical example probe fingerprint changed')
    inventory = report['pair_inventory']
    counts = Counter(row['status'] for row in inventory['pairs'])
    if (inventory['run_scope'] != 'representative'
            or inventory['total_pairs'] != 8911
            or len(inventory['pairs']) != 8911
            or counts != {'checked': 528, 'intentionally_omitted': 8383}):
        raise ValueError('historical representative scope or counts changed')


def check_pinned_example(path):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != REPORT_SHA256:
        raise ValueError('historical example checksum changed')
    check_metadata(json.loads(data))


class PinnedPairExampleTests(unittest.TestCase):
    def test_example_is_pinned_to_its_recorded_source_not_current_head(self):
        check_pinned_example(EXAMPLE)
        text = (ROOT / 'docs/validation/anatomy-pairs-596.md').read_text()
        self.assertIn(SOURCE_COMMIT, text)
        self.assertIn('not a report of the current checkout', text)

    def test_changed_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'example.json'
            path.write_bytes(EXAMPLE.read_bytes() + b' ')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                check_pinned_example(path)

    def test_changed_binding_or_scope_is_rejected(self):
        original = json.loads(EXAMPLE.read_text())
        mutations = [
            lambda r: r['build_provenance'].update(source_sha256='0' * 64),
            lambda r: r['build_provenance'].update(binary_sha256='0' * 64),
            lambda r: r['pair_inventory'].update(run_scope='full'),
            lambda r: r['pair_inventory'].update(total_pairs=8910),
            lambda r: r['pair_inventory']['pairs'][0].update(status='unsupported'),
        ]
        for mutate in mutations:
            report = copy.deepcopy(original)
            mutate(report)
            with self.assertRaises(ValueError):
                check_metadata(report)


if __name__ == '__main__':
    unittest.main()
