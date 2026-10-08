# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fail-closed migration and premise controls for reviewed CARLA cleanups."""
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import reviewed_cleanup_contracts as cleanup
import frozen_arc_producer_contracts as frozen
import source_contracts as source
import sum2_guard_contracts as guard
import winner_sign_contracts as winner

ROOT = Path(__file__).resolve().parents[2]


class ReviewedCleanupContracts(unittest.TestCase):
    def test_positive_source_and_exact_historical_scope(self):
        record = cleanup.verify(ROOT)
        result = winner.verify(ROOT)
        self.assertEqual(result['canonical_dependencies_unchanged'], 98)
        self.assertEqual(result['reviewed_cleanup_successors'], 14)
        self.assertFalse(result['native_qualification_claimed'])
        prior = json.loads((ROOT/winner.MIGRATION).read_text())
        self.assertEqual(len(prior['canonical_source_unchanged']), 112)
        for path, transition in record['sources'].items():
            self.assertEqual(prior['canonical_source_unchanged'][path],
                             transition['before_sha256'])

    def test_only_three_runtime_pins_change_and_guard_pins_stay_identical(self):
        record = cleanup.read_record(ROOT)
        runtime = json.loads(cleanup.invariant.predecessor_pins(ROOT, source.PINS))
        # First reconstruct the accepted three-successor checkpoint. Its
        # historical record and original three-entry assertions stay intact.
        fourth = frozen.read_record(ROOT)
        for item in fourth['runtime_token_successors']:
            self.assertEqual(runtime['groups'][item['group']][item['path']], item['after'])
            runtime['groups'][item['group']][item['path']] = item['before']
        predecessor = (json.dumps(runtime, indent=2)+'\n').encode()
        self.assertEqual(hashlib.sha256(predecessor).hexdigest(),
                         record['runtime_pins_after_sha256'])
        transitions = record['runtime_token_successors']
        self.assertEqual({(item['group'], item['path']) for item in transitions}, {
            ('eligibility', cleanup.SOURCE_PATHS[0]),
            ('eligibility', cleanup.SOURCE_PATHS[1]),
            ('support', cleanup.SOURCE_PATHS[2]),
        })
        self.assertEqual(len(transitions), 3)
        for item in transitions:
            self.assertEqual(runtime['groups'][item['group']][item['path']], item['after'])
            runtime['groups'][item['group']][item['path']] = item['before']
        prior_bytes = (json.dumps(runtime, indent=2)+'\n').encode()
        self.assertEqual(hashlib.sha256(prior_bytes).hexdigest(),
                         record['runtime_pins_before_sha256'])
        pins = json.loads(cleanup.invariant.predecessor_pins(ROOT, guard.PINS))
        self.assertEqual(record['unchanged_protected_inventory'], {
            cleanup.SOURCE_PATHS[2]: pins['protected_inventory'][cleanup.SOURCE_PATHS[2]],
        })
        self.assertEqual(hashlib.sha256(cleanup.invariant.predecessor_pins(ROOT, guard.PINS)).hexdigest(),
                         record['guard_pins_before_sha256'])
        self.assertEqual(record['guard_pins_before_sha256'],
                         record['guard_pins_after_sha256'])

    def test_native_outward_reference_keeps_original_body(self):
        text = (ROOT/'tests/test_carla_outward_float_equivalence.mojo').read_text()
        reference = guard.declaration(text, '_reference_outward_float', ())
        self.assertEqual(source.token_sha256(reference),
                         cleanup.read_record(ROOT)['frozen_outward_reference_token_sha256'])

    def test_removed_check_premises_reject_mutations_without_digest_gate(self):
        cases = (
            (0, 'len(road.info.geometries) != 1', 'len(road.info.geometries) < 1'),
            (0, 'not _RoundedBox.bounds(low, high).known', 'False'),
            (0, 'info_index(road.info.geometries, low) != 0',
             'info_index(road.info.geometries, high) != 0'),
            (0, 'info_index(road.info.lane_offsets, high) != offset_at', 'False'),
            (0, 'info_index(road.info.elevations, high) != elevation_at', 'False'),
            (0, 'info_index(widths, high) != width_at', 'False'),
            (1, 'len(road.info.geometries) != 1', 'len(road.info.geometries) < 1'),
            (1, 'info_index(road.info.geometries, low) != 0', 'False'),
            (1, 'len(road.info.lane_offsets) != 1', 'False'),
            (1, 'len(road.info.elevations) != 1', 'False'),
            (1, 'info_index(road.info.lane_offsets, low) != 0', 'False'),
            (1, 'info_index(road.info.elevations, low) != 0', 'False'),
            (1, 'len(widths) != 1', 'len(widths) < 1'),
            (1, 'info_index(widths, low) != 0', 'False'),
            (1, 'and low <= high', 'and low >= high'),
            (1, 'if not half.known:', 'if False:'),
            (1, 'selector.low < 0.0', 'selector.low < -1.0'),
            (1, 'selector.high >= 1.0', 'selector.high > 1.0'),
            (2, 'outside = Float64(result) > value', 'outside = Float64(result) < value'),
            (2, 'outside = Float64(result) < value', 'outside = Float64(result) > value'),
            (2, 'UInt32(0x80000001) if lower else UInt32(1)',
             'UInt32(1) if lower else UInt32(0x80000001)'),
            (2, 'if (result > 0.0) == lower:', 'if (result > 0.0) != lower:'),
        )
        read = Path.read_text
        for index, before, after in cases:
            path = ROOT/cleanup.SOURCE_PATHS[index]
            original = path.read_text()
            self.assertEqual(original.count(before), 1)
            changed = original.replace(before, after, 1)
            with self.subTest(path=path.name, mutation=before), patch.object(
                    Path, 'read_text', lambda p, *a, **k:
                    changed if p == path else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, 'unreviewed complete successor'):
                    cleanup.verify(ROOT)
                with self.assertRaises(ValueError):
                    cleanup.verify_premises(ROOT)

    def test_manifest_change_cannot_refresh_the_review(self):
        path = ROOT/cleanup.MIGRATION
        original = path.read_bytes()
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p, *a, **k:
                          original+b' ' if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed migration'):
                cleanup.verify(ROOT)

    def test_comments_cannot_supply_missing_premises(self):
        with self.assertRaises(ValueError):
            cleanup.ordered('# if len(widths) != 1: return None\n',
                            ('if len(widths) != 1: return None',), 'missing singleton')


if __name__ == '__main__':
    unittest.main()
