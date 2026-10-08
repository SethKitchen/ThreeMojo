# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact operation and predecessor controls for two private successors."""
from pathlib import Path
import unittest
import hashlib
from unittest.mock import patch
import curve_support_dispatch_contracts as contract

ROOT = Path(__file__).resolve().parents[2]


class CurveSupportDispatchContracts(unittest.TestCase):
    def test_complete_positive_and_immutable_historical_inputs(self):
        contract.verify(ROOT)
        import coverage_invariant_contracts as invariant
        for path, expected in contract.read_record(ROOT)['historical_pins'].items():
            payload = (invariant.predecessor_pins(ROOT, path)
                       if Path(path).name in invariant.read_record(ROOT)['pin_files']
                       else (ROOT/path).read_bytes())
            self.assertEqual(hashlib.sha256(payload).hexdigest(), expected)

    def test_independent_operation_mutations_are_rejected(self):
        cases = [
            ('curve_minimizer_support', 'or best < low', 'or False'),
            ('curve_minimizer_support', 'or domain.error < 0.0', 'or False'),
            ('curve_minimizer_support', 'domain.second.low > 0.0', 'domain.second.low >= 0.0'),
            ('curve_minimizer_support', '_Interval.point(2.0) *', '_Interval.point(-2.0) *'),
            ('curve_minimizer_support', '_Interval.point(4.0) *', '_Interval.point(-4.0) *'),
            ('curve_minimizer_support', 'result.high = min(result.high, limit.high)', 'result.high = min(result.high, limit.low)'),
            ('curve_minimizer_support', 'result.low = max(result.low, limit.low)', 'result.low = max(result.low, limit.high)'),
            ('curve_sample_dispatch', 'if count < 1 or count > 2:', 'if count < 0 or count > 2:'),
            ('curve_sample_dispatch', 'first + i + 1', 'first + i'),
            ('curve_sample_dispatch', 'if station > high:', 'if station < high:'),
            ('curve_sample_dispatch', 'after_index != threshold_at', 'after_index == threshold_at'),
            ('curve_sample_dispatch', 'var node_reserve = 3 * count + 2', 'var node_reserve = count'),
            ('curve_sample_dispatch', 'terms += extra', 'terms += 1'),
            ('curve_sample_dispatch', 'local >= length', 'local > length'),
            ('curve_interval', 'Self(_next_down(low), _next_up(high))', 'Self(low, high)'),
            ('curve_interval', 'return Self(-self.high, -self.low)', 'return Self(-self.low, -self.high)'),
            ('curve_interval', 'if other.contains(0.0):', 'if False:'),
            ('curve_interval', 'if self.low < 0.0:', 'if self.low > 0.0:'),
            ('curve_bounds', 'var high = len(geometry.samples) - 1', 'var high = len(geometry.samples)'),
            ('curve_bounds', 'geometry.samples[middle].s < d', 'geometry.samples[middle].s <= d'),
            ('map', '_require_sum2_environment()', 'pass'),
            ('lane_refinement', '_require_sum2_environment()', 'pass'),
            ('curve_sum2', 'def _sum2_supported_environment()', 'def _unchecked_environment()'),
        ]
        read = Path.read_text
        for module, before, after in cases:
            path = ROOT/f'extensions/carla/{module}.mojo'
            original = path.read_text()
            self.assertIn(before, original)
            changed = original.replace(before, after)
            with self.subTest(module=module, before=before), patch.object(
                    Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
                with self.assertRaises(ValueError):
                    contract.verify_premises(ROOT)

    def test_record_refresh_cannot_authorize_change(self):
        target = ROOT/contract.MIGRATION
        read = Path.read_bytes
        original = read(target)
        with patch.object(Path, 'read_bytes', lambda p, *a, **k:
                          original+b' ' if p == target else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed migration'):
                contract.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
