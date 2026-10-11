# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the #595 overlap evidence, its bindings and its classification."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import anatomy_overlaps as ao
import anatomy_validity as av

ROOT = Path(__file__).resolve().parent.parent
CURRENT = ROOT / 'docs/validation/anatomy-overlaps-595.json'
BEFORE = ROOT / 'docs/validation/anatomy-overlaps-595-before.json'
# The localization of the unrepaired template. Its source is the commit that
# added the witness probe and changed no anatomy.
BEFORE_SHA256 = 'fd1f2d1de0c62b4a8a78a69cf0ec8a099da542c6958441c71f68fcb5a1aeb03e'
BEFORE_SOURCE_SHA256 = 'd984741bb8496a606e68649a5f6428107baa195e0aaca99ddf470985fdf06529'
# The 5 mm sample counts that #595 quotes.
ISSUE_COUNTS = {
    'canonical/bones/foot/talus|tibia': 14,
    'canonical/bones/foot/first_metatarsal|foot/medial_cuneiform': 17,
    'canonical/knee/femur|knee/mcl': 28,
    'canonical/knee/knee/lcl|tibia': 2,
    'canonical/spine/cervical/2|cervical/3': 1,
}


def check_record(report):
    """Refuse evidence whose shape or status does not follow its samples."""
    if report['schema_version'] != ao.SCHEMA_VERSION or report['steps_mm'] != list(ao.STEPS_MM):
        raise ValueError('overlap evidence has a different schema or grid')
    listed = {pair['pair_id'] for pair in report['pairs'] if pair['listed_in_issue_595']}
    if listed != set(ao.ISSUE_595_PAIRS):
        raise ValueError('overlap evidence does not track every issue pair')
    for pair in report['pairs']:
        if len(pair['grids']) != len(ao.STEPS_MM):
            raise ValueError('a tracked pair is missing a grid width')
        if pair['interface_rule'] not in ao.RULES or pair['classification'] not in ao.CLASSES:
            raise ValueError('a tracked pair has an unknown rule or class')
        for grid in pair['grids']:
            if grid['samples'] > 0 and grid['witness_point_m'] is None:
                raise ValueError('a sampled pair has no witness point')
            if (grid['overlap_samples'] > 0) != ('hit_center_low_m' in grid):
                raise ValueError('common-interior cells and their box disagree')
        if pair['status'] != ao.status(pair['grids']):
            raise ValueError('a pair status does not follow its samples')
    return report


def check_current(path, root=ROOT):
    """The live evidence must match the current source and tool."""
    report = check_record(json.loads(path.read_text()))
    if report['build_provenance']['source_sha256'] != av.source_digest(root):
        raise ValueError('overlap evidence has a stale source binding; regenerate with '
                         'python3 tools/anatomy_overlaps.py --build --output '
                         'docs/validation/anatomy-overlaps-595.json')
    if report['tool_sha256'] != ao.tool_sha256(root):
        raise ValueError('overlap evidence has a stale tool binding')
    return report


def check_before(path):
    """The unrepaired localization is pinned to its recorded source."""
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != BEFORE_SHA256:
        raise ValueError('pinned overlap localization checksum changed')
    report = check_record(json.loads(data))
    if report['build_provenance']['source_sha256'] != BEFORE_SOURCE_SHA256:
        raise ValueError('pinned overlap localization source binding changed')
    return report


class OverlapClassificationTests(unittest.TestCase):
    def test_every_issue_pair_has_a_rule_and_a_class(self):
        self.assertEqual(len(set(ao.ISSUE_595_PAIRS)), 36)
        groups = [pair.split('/')[1] for pair in ao.ISSUE_595_PAIRS]
        self.assertEqual((groups.count('bones'), groups.count('knee'), groups.count('spine')),
                         (21, 14, 1))
        for pair in ao.ISSUE_595_PAIRS:
            self.assertIn(pair, ao.CLASSIFICATION)
        for rule, kind, note in ao.CLASSIFICATION.values():
            self.assertIn(rule, ao.RULES)
            self.assertIn(kind, ao.CLASSES)
            self.assertTrue(note)

    def test_status_follows_samples_and_refinement(self):
        clear = {'overlap_samples': 0, 'refined_field_witness_m': 2e-9}
        self.assertEqual(ao.status([clear, clear]), 'no_common_interior_sampled')
        self.assertEqual(ao.status([clear, dict(clear, overlap_samples=1)]),
                         'common_interior_found')
        self.assertEqual(ao.status([clear, dict(clear, refined_field_witness_m=-1e-9)]),
                         'common_interior_found')
        self.assertEqual(ao.status([{'overlap_samples': 0}]), 'no_common_interior_sampled')

    def test_witness_requests_name_supported_pairs_only(self):
        labels = {'tibia': 1, 'foot/talus': 9}
        self.assertEqual(ao.witness_request('bones', {'first': 'tibia', 'second': 'foot/talus'}, labels),
                         ('pairs', 'witness:1:9'))
        self.assertEqual(ao.witness_request('spine', {'first': 'cervical/2', 'second': 'cervical/3',
                                                      'pair_id': 'x'}, labels),
                         ('spine-witness', 'cervical/2'))
        for second in ('cervical/2/disc', 'cervical/5', 'thoracolumbar/0'):
            with self.assertRaises(ValueError):
                ao.witness_request('spine', {'first': 'cervical/2', 'second': second,
                                             'pair_id': 'x'}, labels)

    def test_a_witness_pass_must_repeat_its_grid(self):
        row = {'samples': 10, 'overlap_samples': 1, 'overlap_volume_m3': 1e-7,
               'signed_field_witness_m': -1e-4}
        ao.check_witness(dict(row), row)
        for key, value in (('samples', 9), ('overlap_samples', 0),
                           ('overlap_volume_m3', 2e-7), ('signed_field_witness_m', -2e-4)):
            with self.assertRaises(ValueError):
                ao.check_witness(dict(row, **{key: value}), row)


class OverlapEvidenceTests(unittest.TestCase):
    def test_current_evidence_matches_the_current_source(self):
        report = check_current(CURRENT)
        for pair in report['pairs']:
            self.assertEqual(pair['status'], 'no_common_interior_sampled', pair['pair_id'])
        for counts in report['pairs_with_sampled_common_interior'].values():
            self.assertEqual(counts, {'bones': 0, 'knee': 0, 'spine': 0})

    def test_unrepaired_localization_is_pinned_and_shows_each_issue_pair(self):
        report = check_before(BEFORE)
        pairs = {pair['pair_id']: pair for pair in report['pairs']}
        for pair_id in ao.ISSUE_595_PAIRS:
            pair = pairs[pair_id]
            self.assertEqual(pair['status'], 'common_interior_found')
            five = pair['grids'][0]
            self.assertGreater(five['overlap_samples'], 0)
            self.assertLess(five['refined_field_witness_m'], 0)
        for pair_id, count in ISSUE_COUNTS.items():
            self.assertEqual(pairs[pair_id]['grids'][0]['overlap_samples'], count)
        text = (ROOT / 'docs/validation/anatomy-overlaps-595.md').read_text()
        self.assertIn(BEFORE_SOURCE_SHA256, text)

    def test_changed_evidence_is_rejected(self):
        original = json.loads(CURRENT.read_text())
        mutations = [
            lambda r: r.update(steps_mm=[5.0, 3.0]),
            lambda r: r['pairs'].pop(),
            lambda r: r['pairs'][0].update(status='common_interior_found'),
            lambda r: r['pairs'][0].update(interface_rule='allowance'),
            lambda r: r['pairs'][0]['grids'].pop(),
            lambda r: r['pairs'][0]['grids'][0].update(overlap_samples=1),
        ]
        for mutate in mutations:
            report = copy.deepcopy(original)
            mutate(report)
            with self.assertRaises(ValueError):
                check_record(report)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'before.json'
            path.write_bytes(BEFORE.read_bytes() + b' ')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                check_before(path)
            stale = copy.deepcopy(original)
            stale['build_provenance']['source_sha256'] = '0' * 64
            path.write_text(json.dumps(stale))
            with self.assertRaisesRegex(ValueError, 'stale source'):
                check_current(path)
            stale = copy.deepcopy(original)
            stale['tool_sha256'] = '0' * 64
            path.write_text(json.dumps(stale))
            with self.assertRaisesRegex(ValueError, 'stale tool'):
                check_current(path)


if __name__ == '__main__':
    unittest.main()
