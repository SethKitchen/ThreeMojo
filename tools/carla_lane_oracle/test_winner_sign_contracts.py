# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Meaningful mutation controls for the reviewed combined Map migration."""
from pathlib import Path
import unittest
from unittest.mock import patch

import sum2_guard_contracts as guard
import winner_sign_contracts as contracts

ROOT = Path(__file__).resolve().parents[2]


class WinnerSignContracts(unittest.TestCase):
    def test_source_correspondence_and_distinct_lexical_owners(self):
        result = contracts.verify(ROOT)
        self.assertEqual(result['source_bound_helpers'], 4)
        self.assertEqual(result['fresh_environment_entries'], 2)
        self.assertFalse(result['native_qualification_claimed'])
        text = (ROOT/'extensions/carla/map.mojo').read_text()
        for name in ('_seed_exact_interval', '_seed_reference_domain',
                     '_winner_seed_room', '_try_winner_seed'):
            guard.declaration(text, name, ())
            with self.assertRaisesRegex(ValueError, 'owner/scope'):
                guard.declaration(text, name, ('Map',))
        with self.assertRaisesRegex(ValueError, 'owner/scope'):
            guard.declaration(text, '_closest_lane_certificate_with_work', ())

    def test_disabled_or_underpriced_optional_routes_reject(self):
        path = ROOT/'extensions/carla/map.mojo'
        original = path.read_text()
        replacements = (
            ('work._step(60)', 'work._step(59)'),
            ('var winner_followup = len(winner.cells) + 12',
             'var winner_followup = len(winner.cells) + 11'),
            ('var target_followup = target_cells + 12',
             'var target_followup = target_cells + 11'),
            ('var winner_units = proof_nodes + 255 + 50',
             'var winner_units = proof_nodes + 255 + 49'),
            ('return target_reference <= terms_left // 50',
             'return target_reference <= terms_left // 49'),
            ('if _wide_point_order(point, certificate.point, query) < 0:',
             'if _wide_point_order(point, certificate.point, query) <= 0:'),
            ('work.charge(0, point_work, node_cost)',
             'work.charge(0, 0, node_cost)'),
        )
        read = Path.read_text
        for before, after in replacements:
            self.assertEqual(original.count(before), 1)
            changed = original.replace(before, after, 1)
            with self.subTest(before=before), patch.object(
                    Path, 'read_text', lambda p, *a, **k:
                    changed if p == path else read(p, *a, **k)):
                with self.assertRaises(ValueError):
                    contracts.verify(ROOT)
                # Independently exercise complete helper contracts, without
                # letting the raw whole-Map digest hide a missing caller pin.
                with self.assertRaisesRegex(ValueError, 'complete guarded caller'):
                    guard.verify(ROOT)

    def test_fresh_guard_precedes_any_optional_work(self):
        text = (ROOT/'extensions/carla/map.mojo').read_text()
        for name in ('_seed_reference_domain', '_try_winner_seed'):
            declaration = guard.declaration(text, name, ())
            contracts.fresh_guard(declaration)
            for replacement in ('', '    var cached = True\n'):
                changed = declaration.replace('    _require_sum2_environment()\n', replacement, 1)
                self.assertNotEqual(changed, declaration)
                with self.assertRaisesRegex(ValueError, 'first operation'):
                    contracts.fresh_guard(changed)

    def test_manifest_edits_cannot_refresh_the_review(self):
        path = ROOT/contracts.MIGRATION
        original = path.read_bytes()
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p, *a, **k:
                          original+b' ' if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed migration'):
                contracts.verify(ROOT)

    def test_comments_cannot_supply_required_fee_operations(self):
        with self.assertRaises(ValueError):
            contracts.contains('# work._step(60)\n', 'work._step(60)', 'missing fee')


if __name__ == '__main__':
    unittest.main()
