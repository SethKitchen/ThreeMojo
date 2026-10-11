# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Producer, constructor, and Box controls for the immediate ARC consumer."""
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import frozen_arc_producer_contracts as frozen
import reviewed_cleanup_contracts as cleanup
import source_contracts as source
import sum2_guard_contracts as guard

ROOT = Path(__file__).resolve().parents[2]
ARC = 'extensions/carla/curve_rounded_arc.mojo'


class FrozenArcProducerContracts(unittest.TestCase):
    def test_complete_scoped_positive_and_retained_predecessor(self):
        record = frozen.verify(ROOT)
        self.assertEqual(frozen.verify_premises(ROOT), 17)
        self.assertEqual(hashlib.sha256((ROOT/cleanup.MIGRATION).read_bytes()).hexdigest(),
                         record['previous_cleanup_migration_sha256'])
        self.assertEqual(cleanup.read_record(ROOT)['runtime_pins_after_sha256'],
                         record['runtime_pins_before_sha256'])
        historical = cleanup.read_record(ROOT)
        self.assertEqual(len(historical['sources']), 3)
        original = json.loads((ROOT/'tools/carla_lane_oracle/winner-sign-query-migration.json').read_text())
        self.assertEqual(len(original['canonical_source_unchanged']), 112)
        self.assertEqual(len(original['canonical_source_unchanged']) - len(historical['sources']), 109)
        self.assertEqual(record['source_successor']['path'], frozen.SOURCE_PATH)

    def test_three_new_pin_placements_reconstruct_exact_predecessor(self):
        record = frozen.read_record(ROOT)
        pins = json.loads(cleanup.invariant.predecessor_pins(ROOT, source.PINS))
        changes = record['runtime_token_successors']
        self.assertEqual({(item['group'], item['path']) for item in changes}, {
            ('eligibility', frozen.SOURCE_PATH),
            ('optional_runtime', frozen.SOURCE_PATH),
            ('translation', frozen.SOURCE_PATH),
        })
        self.assertEqual(len(changes), 3)
        for item in changes:
            self.assertEqual(pins['groups'][item['group']][item['path']], item['after'])
            pins['groups'][item['group']][item['path']] = item['before']
        restored = (json.dumps(pins, indent=2)+'\n').encode()
        self.assertEqual(hashlib.sha256(restored).hexdigest(),
                         record['runtime_pins_before_sha256'])

    def test_frozen_native_reference_is_the_original_consumer(self):
        text = (ROOT/'tests/test_carla_frozen_arc_producer_contract.mojo').read_text()
        reference = guard.declaration(text, '_reference_frozen_arc_context', ())
        self.assertEqual(source.token_sha256(reference),
                         frozen.read_record(ROOT)['frozen_reference_token_sha256'])

    def test_producer_box_constructor_and_consumer_mutations_reject(self):
        # Each tuple changes one actual body or declaration. The scoped gate
        # must reject independently of the complete successor/module digest.
        cases = (
            (ARC, 'return Self.bounds(value, value)', 'return Self.bounds(value, value + 1.0)'),
            (ARC, 'return Self(0.0, 0.0, False)', 'return Self(0.0, 0.0, True)'),
            (ARC, 'return Self(low, high, valid)', 'return Self(low, high, True)'),
            (ARC, 'return Self(-self.high, -self.low, self.known)',
             'return Self(-self.high, -self.low, True)'),
            (ARC, '_rounded_add(self.high, other.high)', '_rounded_add(self.high, other.high) + 1.0'),
            (ARC, 'return self + (-other)', 'return self + other'),
            (ARC, 'return separate.hull(_RoundedBox.bounds(low, high))', 'return separate'),
            (ARC, 'var d = _rounded_multiply(self.high, other.high)',
             'var d = _rounded_fma(self.high, other.high, 1.0)'),
            (ARC, '@no_inline\ndef _rounded_add(', 'def _rounded_add('),
            (ARC, '    return a + b\n', '    return fma(1.0, a, b)\n'),
            (ARC, '    return a * b\n', '    return fma(a, b, 1.0)\n'),
            (ARC, '    return 1.0 / value\n', '    return value\n'),
            (ARC, 'return _RoundedBox.point(polynomial.a)',
             'return _RoundedBox.bounds(polynomial.a, polynomial.a + 1.0)'),
            (ARC, 'if not lane_offset.known or not elevation.known:', 'if False:'),
            (ARC, 'if not width.known:', 'if False:'),
            (ARC, 'if not curvature.known or curvature.low == 0.0 or not offset.known:',
             'if curvature.low == 0.0:'),
            (ARC, 'if not (speed.known and x.known and y.known and start.known):', 'if False:'),
            (ARC, 'var speed = (radius + offset) * curvature',
             'var speed = _rounded_madd(radius + offset, curvature, _RoundedBox.point(0.0))'),
            (ARC, 'start, record.geometry.length, curvature, speed, x, y, elevation',
             'start, record.geometry.length, curvature, speed, y, x, elevation'),
            (ARC, 'var start: _RoundedBox\n    var length: Float64',
             'var length: Float64\n    var start: _RoundedBox'),
            (frozen.SOURCE_PATH, 'var found = _rounded_arc_context(road, section, lane, low, high)',
             'var found = other_arc_context(road, section, lane, low, high)'),
            (frozen.SOURCE_PATH, 'if not found:', 'if False:'),
            (frozen.SOURCE_PATH, 'not distance.known', 'False'),
            (frozen.SOURCE_PATH, 'or distance.low <= 0.0', 'or False'),
            (frozen.SOURCE_PATH, 'or distance.high >= model.length', 'or False'),
            (frozen.SOURCE_PATH, '    return model\n',
             '    model.start = _RoundedBox.unknown()\n    return model\n'),
        )
        read = Path.read_text
        for name, before, after in cases:
            path = ROOT/name
            original = path.read_text()
            self.assertEqual(original.count(before), 1)
            changed = original.replace(before, after, 1)
            with self.subTest(path=path.name, mutation=before), patch.object(
                    Path, 'read_text', lambda p, *a, **k:
                    changed if p == path else read(p, *a, **k)):
                with self.assertRaises(ValueError):
                    frozen.verify(ROOT)
                with self.assertRaisesRegex(ValueError, 'complete producer/Box|field layout'):
                    frozen.verify_premises(ROOT)

    def test_manifest_and_runtime_pin_refresh_cannot_authorize_change(self):
        read = Path.read_bytes
        for relative, diagnostic in ((frozen.MIGRATION, 'unreviewed migration'),
                                     (str(source.PINS), 'unreviewed runtime pin')):
            path = ROOT/relative
            original = path.read_bytes()
            with self.subTest(path=relative), patch.object(
                    Path, 'read_bytes', lambda p, *a, **k:
                    original+b' ' if p == path else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, diagnostic):
                    frozen.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
